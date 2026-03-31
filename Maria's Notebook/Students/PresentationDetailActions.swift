import Foundation
import OSLog
import SwiftUI
import CoreData

@Observable
@MainActor
final class PresentationDetailActions {
    private static let logger = Logger.students

    // swiftlint:disable:next function_parameter_count
    func applyEditsToModel(
        lessonAssignment: CDLessonAssignment,
        editingLessonID: UUID,
        scheduledFor: Date?,
        givenAt: Date?,
        isPresented: Bool,
        notes: String,
        needsAnotherPresentation: Bool,
        selectedStudentIDs: Set<UUID>,
        studentsAll: [CDStudent],
        lessons: [CDLesson],
        calendar: Calendar
    ) {
        // Do not allow zero-student lessons; skip applying edits if empty selection
        guard !selectedStudentIDs.isEmpty else { return }

        lessonAssignment.lessonID = editingLessonID.uuidString
        lessonAssignment.notes = notes
        lessonAssignment.needsAnotherPresentation = needsAnotherPresentation
        lessonAssignment.studentIDs = selectedStudentIDs.map(\.uuidString)
        lessonAssignment.lesson = lessons.first(where: { $0.id == editingLessonID })

        // State transitions: presented > scheduled > draft
        if isPresented {
            let date = givenAt ?? Date()
            lessonAssignment.markPresented(at: calendar.startOfDay(for: date))
        } else {
            if lessonAssignment.state == .presented {
                lessonAssignment.presentedAt = nil
            }
            lessonAssignment.setScheduledFor(scheduledFor, using: calendar)
        }
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity function_parameter_count
    func autoCreateNextIfNeeded(
        wasGiven: Bool,
        nowGiven: Bool,
        nextLesson: CDLesson?,
        selectedStudentIDs: Set<UUID>,
        studentsAll: [CDStudent],
        lessons: [CDLesson],
        lessonAssignmentsAll: [CDLessonAssignment],
        context: NSManagedObjectContext
    ) {
        #if DEBUG
        // swiftlint:disable:next line_length
        Self.logger.debug("autoCreateNextIfNeeded: wasGiven=\(wasGiven, privacy: .public), nowGiven=\(nowGiven, privacy: .public), hasNextLesson=\(nextLesson != nil, privacy: .public)")
        #endif
        
        guard !wasGiven, nowGiven, let next = nextLesson else {
            #if DEBUG
            if wasGiven {
                Self.logger.debug("Skipping: lesson was already given")
            } else if !nowGiven {
                Self.logger.debug("Skipping: lesson not marked as given yet")
            } else if nextLesson == nil {
                Self.logger.debug("Skipping: no next lesson in sequence")
            }
            #endif
            return
        }

        #if DEBUG
        Self.logger.debug(
            "Creating next lesson: \(next.name) for \(selectedStudentIDs.count, privacy: .public) students"
        )
        #endif

        // Fetch LessonAssignments for duplicate checking (service now expects CDLessonAssignment)
        let lessonAssignments: [CDLessonAssignment]
        do {
            lessonAssignments = try context.fetch(NSFetchRequest<CDLessonAssignment>(entityName: "LessonAssignment"))
        } catch {
            Self.logger.warning("Failed to fetch LessonAssignments: \(error)")
            lessonAssignments = []
        }

        let result = PlanNextLessonService.planLesson(
            next,
            forStudents: selectedStudentIDs,
            allStudents: studentsAll,
            allLessons: lessons,
            existingLessonAssignments: lessonAssignments,
            context: context
        )

        #if DEBUG
        switch result {
        case .success(let presentation):
            Self.logger.info("Successfully created next lesson (ID: \(presentation.id?.uuidString ?? "nil", privacy: .public))")
        case .alreadyExists:
            Self.logger.warning("Next lesson already exists in inbox")
        case .noNextLesson:
            Self.logger.warning("No next lesson found")
        case .noCurrentLesson:
            Self.logger.warning("Current lesson not found")
        case .emptySubjectOrGroup:
            Self.logger.warning("Empty subject or group")
        case .noStudents:
            Self.logger.warning("No students selected")
        }
        #endif

        if case .success = result {
            PresentationDetailUtilities.notifyInboxRefresh()
        }
    }

    // swiftlint:disable:next function_parameter_count
    func planNextLessonInGroup(
        next: CDLesson,
        selectedStudentIDs: Set<UUID>,
        studentsAll: [CDStudent],
        lessons: [CDLesson],
        lessonAssignmentsAll: [CDLessonAssignment],
        context: NSManagedObjectContext
    ) -> Bool {
        // Fetch LessonAssignments for duplicate checking (service now expects CDLessonAssignment)
        let lessonAssignments: [CDLessonAssignment]
        do {
            lessonAssignments = try context.fetch(NSFetchRequest<CDLessonAssignment>(entityName: "LessonAssignment"))
        } catch {
            Self.logger.warning("Failed to fetch LessonAssignments: \(error)")
            lessonAssignments = []
        }

        let result = PlanNextLessonService.planLesson(
            next,
            forStudents: selectedStudentIDs,
            allStudents: studentsAll,
            allLessons: lessons,
            existingLessonAssignments: lessonAssignments,
            context: context
        )

        if case .success = result {
            context.safeSave()
            PresentationDetailUtilities.notifyInboxRefresh()
            return true
        }
        return false
    }

    func moveStudentsToInbox(
        currentLesson: CDLesson,
        studentsToMove: Set<UUID>,
        studentsAll: [CDStudent],
        lessonAssignmentsAll: [CDLessonAssignment],
        context: NSManagedObjectContext
    ) -> [String] {
        guard !studentsToMove.isEmpty else { return [] }

        let movedStudentNames = studentsAll
            .filter { guard let sid = $0.id else { return false }; return studentsToMove.contains(sid) }
            .map { StudentFormatter.displayName(for: $0) }

        let currentLessonID = currentLesson.id ?? UUID()
        let targetSet = studentsToMove
        let existing = lessonAssignmentsAll.first(where: { la in
            la.resolvedLessonID == currentLessonID && la.scheduledFor == nil
                && !la.isPresented && Set(la.resolvedStudentIDs) == targetSet
        })

        if let ex = existing {
            ex.studentIDs = studentsAll.compactMap(\.id).filter { targetSet.contains($0) }.map(\.uuidString)
            ex.lesson = currentLesson
        } else {
            let newLA = PresentationFactory.makeDraft(
                lesson: currentLesson,
                students: studentsAll.filter { guard let sid = $0.id else { return false }; return targetSet.contains(sid) },
                context: context
            )
            _ = newLA // Core Data auto-inserts into context
        }

        context.safeSave()
        PresentationDetailUtilities.notifyInboxRefresh()
        return movedStudentNames
    }

    func toggleWorkCompletion(_ work: CDWorkModel, studentID: UUID, context: NSManagedObjectContext) {
        if work.isStudentCompleted(studentID) {
            // Un-complete: Remove from participant (historical records preserved)
            if let participant = work.participant(for: studentID) {
                participant.completedAt = nil
            }
        } else {
            // Complete: Use WorkCompletionService for proper historical tracking
            do {
                try WorkCompletionService.markCompleted(workID: work.id ?? UUID(), studentID: studentID, in: context)
                // Also update participant for backwards compatibility
                if let participant = work.participant(for: studentID) {
                    participant.completedAt = Date()
                }
            } catch {
                Self.logger.warning("Error marking work complete: \(error)")
            }
        }
        context.safeSave()
    }

    func nextLessonInGroup(from current: CDLesson?, lessons: [CDLesson]) -> CDLesson? {
        guard let current else { return nil }
        return PlanNextLessonService.findNextLesson(after: current, in: lessons)
    }
}
