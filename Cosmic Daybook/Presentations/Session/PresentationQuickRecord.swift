// PresentationQuickRecord.swift
// The everyday case in one click: Presented on a Ready row.
//
// Records today for the children attendance says were there (an absent child
// stays on the plan, exactly as the sheet's Record does), then applies the
// lesson's own next step to each: Practice when its progression rules require
// practice, otherwise Keep watching. Undo takes all of it back; Details opens
// How It Went on the same record.

import CoreData
import Foundation

enum PresentationQuickRecord {
    struct Receipt {
        let undoToken: ImmediatePresentationRecordingService.UndoToken
        let createdWorkIDs: [NSManagedObjectID]
        let presentIDs: [UUID]
        let keptOnPlan: [UUID]
        let decision: CaptureFollowUp
    }

    static func record(
        _ assignment: CDLessonAssignment,
        lessons: [CDLesson],
        context: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator,
        today: Date = Date()
    ) throws -> Receipt {
        guard let lesson = assignment.lesson else {
            throw PresentationRecorder.RecordError.missingLesson
        }
        let day = AppCalendar.startOfDay(today)
        let planned = Set(assignment.resolvedStudentIDs)
        let absent = PresentationRecorder.absentStudentIDs(on: day, among: planned, context: context)
        let present = planned.subtracting(absent)

        let recorded = try PresentationRecorder.record(
            assignment,
            presentIDs: present,
            on: day,
            context: context,
            saveCoordinator: saveCoordinator
        )
        let presentIDs = assignment.resolvedStudentIDs
        let rules = LessonProgressionRules.resolve(for: lesson, context: context)
        let decision: CaptureFollowUp = rules.requiresPractice ? .practice : .continueObserving

        var createdWorkIDs: [NSManagedObjectID] = []
        if decision == .practice {
            do {
                createdWorkIDs = try applyPractice(
                    assignment, lesson: lesson, studentIDs: presentIDs,
                    lessons: lessons, context: context, saveCoordinator: saveCoordinator
                )
            } catch {
                // All or nothing: a recording without its next step is not
                // what one click promised.
                try? ImmediatePresentationRecordingService.undo(
                    recorded.undoToken, context: context, saveCoordinator: saveCoordinator
                )
                throw error
            }
        }

        return Receipt(
            undoToken: recorded.undoToken,
            createdWorkIDs: createdWorkIDs,
            presentIDs: presentIDs,
            keptOnPlan: recorded.keptOnPlan,
            decision: decision
        )
    }

    // swiftlint:disable:next function_parameter_count
    private static func applyPractice(
        _ assignment: CDLessonAssignment,
        lesson: CDLesson,
        studentIDs: [UUID],
        lessons: [CDLesson],
        context: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator
    ) throws -> [NSManagedObjectID] {
        let decisions = Dictionary(uniqueKeysWithValues: studentIDs.map { ($0, CaptureFollowUp.practice) })
        let receipt = try PresentationSessionCommit.apply(
            PresentationSessionCommit.Input(
                assignment: assignment,
                lesson: lesson,
                studentIDs: studentIDs,
                groupNote: "",
                childNotes: [:],
                decisions: decisions,
                allDecisions: decisions,
                checkIn: .nextWorkCycle,
                lessons: lessons
            ),
            context: context,
            saveCoordinator: saveCoordinator
        )
        return receipt.createdWorkIDs
    }

    /// Takes back the work the click created, then the recording itself.
    static func undo(
        _ receipt: Receipt,
        context: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator
    ) throws {
        let works = receipt.createdWorkIDs.compactMap { id in
            (try? context.existingObject(with: id)) as? CDWorkModel
        }.filter { !$0.isDeleted }
        if !works.isEmpty {
            // The Ready row's toast reports a failure, so the global alert stays quiet.
            try WorkDeletionService(context: context).delete(works) {
                saveCoordinator.save(
                    context, reason: "Undoing a one-click presentation's work", alertOnFailure: false
                )
            }
        }
        try ImmediatePresentationRecordingService.undo(
            receipt.undoToken, context: context, saveCoordinator: saveCoordinator
        )
    }

    /// "Golden Beads: Addition recorded for Ava, Leo and Maya. Practice for
    /// each. Theo was absent and stays on the plan."
    static func message(for receipt: Receipt, lessonName: String, names: [UUID: String]) -> String {
        let present = PresentationSessionSummary.list(receipt.presentIDs.compactMap { names[$0] })
        var parts = ["\(lessonName) recorded for \(present)."]
        if receipt.decision == .practice {
            parts.append(receipt.presentIDs.count == 1 ? "Practice work added." : "Practice work added for each.")
        }
        let kept = receipt.keptOnPlan.compactMap { names[$0] }
        if !kept.isEmpty {
            let verb = kept.count == 1 ? "was absent and stays" : "were absent and stay"
            parts.append("\(PresentationSessionSummary.list(kept)) \(verb) on the plan.")
        }
        return parts.joined(separator: " ")
    }
}
