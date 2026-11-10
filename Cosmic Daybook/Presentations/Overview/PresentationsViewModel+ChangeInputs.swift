// PresentationsViewModel+ChangeInputs.swift
// The hashes `update` compares to decide whether anything moved: everything the
// readiness engine reads, so a change to any of it redraws Ready and Brewing.
// What it reads off the lessons before the Inbox's rows is gathered by
// `InboxPlacement`, which the Class Grid's Brewing mark asks too.

import CoreData
import Foundation

extension PresentationsViewModel {
    /// Computes a hash for CDLessonAssignment change detection
    func computeLessonAssignmentHash(_ assignments: [CDLessonAssignment]) -> Int {
        var hasher = Hasher()
        for la in assignments {
            hasher.combine(la.id)
            hasher.combine(la.scheduledFor?.timeIntervalSinceReferenceDate ?? -1)
            hasher.combine(la.presentedAt?.timeIntervalSinceReferenceDate ?? -1)
            hasher.combine(la.stateRaw)
            hasher.combine(la.notes)
            hasher.combine(la.followUpWork)
            // The stored bytes, not the decoded array: the same bytes always
            // decode to the same ids, and hashing them skips a JSON decode per row.
            hasher.combine(la._studentIDsData)
            hasher.combine(la.needsPractice)
            hasher.combine(la.needsAnotherPresentation)
            hasher.combine(la.lessonID)
            hasher.combine(la.manuallyUnblocked)
            // A confirmation readies a child for the next lesson.
            hasher.combine(la._confirmedStudentIDsData)
        }
        return hasher.finalize()
    }

    /// Computes a hash for CDWorkModel change detection: status, presentation
    /// link, and each child's part (a child who finished her part of shared
    /// work is ready; bug hunt 2026-11-03 #6).
    func computeWorkModelHash(_ workModels: [CDWorkModel]) -> Int {
        var hasher = Hasher()
        for w in workModels {
            hasher.combine(w.id)
            hasher.combine(w.statusRaw)
            hasher.combine(w.presentationID)
            let participants = ((w.participants?.allObjects as? [CDWorkParticipantEntity]) ?? [])
                .sorted { $0.studentID < $1.studentID }
            for participant in participants {
                hasher.combine(participant.studentID)
                hasher.combine(participant.completedAt?.timeIntervalSinceReferenceDate ?? -1)
            }
        }
        return hasher.finalize()
    }

    /// Computes a hash for the roster: a withdrawal or a rename (test
    /// students are picked by name) changes who the backlog shows.
    func computeStudentsHash(_ students: [CDStudent]) -> Int {
        var hasher = Hasher()
        for student in students {
            hasher.combine(student.id)
            hasher.combine(student.enrollmentStatusRaw)
            hasher.combine(student.firstName)
            hasher.combine(student.lastName)
        }
        return hasher.finalize()
    }

    /// The screen's own settings: a change to one re-sorts or re-filters the
    /// backlog with nothing in the store moved.
    static func settingsHash(
        _ inboxOrderRaw: String,
        _ showTestStudents: Bool,
        _ testStudentNamesRaw: String
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(inboxOrderRaw)
        hasher.combine(showTestStudents)
        hasher.combine(testStudentNamesRaw)
        return hasher.finalize()
    }

    /// What the readiness engine reads off each lesson: its place in a
    /// sequence and both rule overrides. Hashing ids alone left Ready and
    /// Brewing as they were after a lesson's rules, area, sequence or position
    /// changed (bug hunt 2026-11-03 #6).
    static func lessonsHash(_ lessons: [CDLesson]) -> Int {
        var hasher = Hasher()
        for lesson in lessons {
            hasher.combine(lesson.id)
            hasher.combine(lesson.area)
            hasher.combine(lesson.sequence)
            hasher.combine(lesson.orderInSequence)
            hasher.combine(lesson.requiresPracticeOverride)
            hasher.combine(lesson.requiresConfirmationOverride)
        }
        return hasher.finalize()
    }

    /// The sub-areas' default rules (`CDLessonSequenceSettings`) and the
    /// mastery marks on the preceding lessons: the rest of what the engine
    /// reads. Order-independent, since neither comes back in a fixed order.
    static func readinessInputsHash(
        sequenceSettings: [CDLessonSequenceSettings],
        masteryMarks: [String: Set<String>]
    ) -> Int {
        var hasher = Hasher()
        let settings = sequenceSettings.filter { !$0.isDeleted }.map { setting in
            "\(setting.area)|\(setting.sequence)|\(setting.requiresPractice)|\(setting.requiresTeacherConfirmation)"
        }
        hasher.combine(settings.sorted())
        for lessonID in masteryMarks.keys.sorted() {
            hasher.combine(lessonID)
            hasher.combine(masteryMarks[lessonID]?.sorted() ?? [])
        }
        return hasher.finalize()
    }
}
