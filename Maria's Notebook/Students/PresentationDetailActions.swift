import Foundation
import OSLog
import SwiftData
import SwiftUI

@Observable
@MainActor
final class PresentationDetailActions {
    private static let logger = Logger.students

    func applyEditsToModel(
        lessonAssignment: LessonAssignment,
        editingLessonID: UUID,
        scheduledFor: Date?,
        givenAt: Date?,
        isPresented: Bool,
        notes: String,
        needsAnotherPresentation: Bool,
        selectedStudentIDs: Set<UUID>,
        studentsAll: [Student],
        lessons: [Lesson],
        calendar: Calendar
    ) {
        // Do not allow zero-student lessons; skip applying edits if empty selection
        guard !selectedStudentIDs.isEmpty else { return }

        lessonAssignment.lessonID = editingLessonID.uuidString
        lessonAssignment.notes = notes
        lessonAssignment.needsAnotherPresentation = needsAnotherPresentation
        lessonAssignment.studentIDs = selectedStudentIDs.map { $0.uuidString }
        lessonAssignment.students = studentsAll.filter { selectedStudentIDs.contains($0.id) }
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

    func autoCreateNextIfNeeded(
        wasGiven: Bool,
        nowGiven: Bool,
        nextLesson: Lesson?,
        selectedStudentIDs: Set<UUID>,
        studentsAll: [Student],
        lessons: [Lesson],
        lessonAssignmentsAll: [LessonAssignment],
        context: ModelContext
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

        // Fetch LessonAssignments for duplicate checking (service now expects LessonAssignment)
        let lessonAssignments: [LessonAssignment]
        do {
            lessonAssignments = try context.fetch(FetchDescriptor<LessonAssignment>())
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
            Self.logger.info("Successfully created next lesson (ID: \(presentation.id, privacy: .public))")
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

    func planNextLessonInGroup(
        next: Lesson,
        selectedStudentIDs: Set<UUID>,
        studentsAll: [Student],
        lessons: [Lesson],
        lessonAssignmentsAll: [LessonAssignment],
        context: ModelContext
    ) -> Bool {
        // Fetch LessonAssignments for duplicate checking (service now expects LessonAssignment)
        let lessonAssignments: [LessonAssignment]
        do {
            lessonAssignments = try context.fetch(FetchDescriptor<LessonAssignment>())
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
        currentLesson: Lesson,
        studentsToMove: Set<UUID>,
        studentsAll: [Student],
        lessonAssignmentsAll: [LessonAssignment],
        context: ModelContext
    ) -> [String] {
        guard !studentsToMove.isEmpty else { return [] }

        let movedStudentNames = studentsAll
            .filter { studentsToMove.contains($0.id) }
            .map { StudentFormatter.displayName(for: $0) }

        let targetSet = studentsToMove
        let existing = lessonAssignmentsAll.first(where: { la in
            la.resolvedLessonID == currentLesson.id && la.scheduledFor == nil
                && !la.isPresented && Set(la.resolvedStudentIDs) == targetSet
        })

        if let ex = existing {
            ex.students = studentsAll.filter { targetSet.contains($0.id) }
            ex.lesson = currentLesson
        } else {
            let newLA = PresentationFactory.makeDraft(
                lessonID: currentLesson.id,
                studentIDs: Array(targetSet)
            )
            PresentationFactory.attachRelationships(
                to: newLA,
                lesson: currentLesson,
                students: studentsAll.filter { targetSet.contains($0.id) }
            )
            context.insert(newLA)
        }

        context.safeSave()
        PresentationDetailUtilities.notifyInboxRefresh()
        return movedStudentNames
    }

    func toggleWorkCompletion(_ work: WorkModel, studentID: UUID, context: ModelContext) {
        if work.isStudentCompleted(studentID) {
            // Un-complete: Remove from participant (historical records preserved)
            if let participant = work.participant(for: studentID) {
                participant.completedAt = nil
            }
        } else {
            // Complete: Use WorkCompletionService for proper historical tracking
            do {
                try WorkCompletionService.markCompleted(workID: work.id, studentID: studentID, in: context)
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

    func nextLessonInGroup(from current: Lesson?, lessons: [Lesson]) -> Lesson? {
        guard let current else { return nil }
        return PlanNextLessonService.findNextLesson(after: current, in: lessons)
    }
}
