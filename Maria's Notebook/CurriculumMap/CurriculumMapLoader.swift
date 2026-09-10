// CurriculumMapLoader.swift
// Reduces the notebook's records to the Sendable refs the engine reads. Runs
// inside `perform` on a background context — the whole snapshot is a handful
// of table scans, which is small at 22 children and a few hundred lessons but
// not something the main actor should do on every sync tick.
//
// Cross-store by design: lessons, presentations and mastery live in the
// shared store, work, practice and recall checks in the private one. They
// join in memory on string ids, as every other screen in the app joins them.

import CoreData
import Foundation

nonisolated enum CurriculumMapLoader {

    /// Call inside `context.perform` on a private-queue context.
    static func snapshot(in context: NSManagedObjectContext) -> CurriculumMapInput {
        var input = CurriculumMapInput()
        input.lessons = lessons(in: context)
        input.students = students(in: context)
        input.presentations = presentations(in: context)
        input.masteries = masteries(in: context)
        input.work = work(in: context)
        input.practice = practice(in: context)
        input.recalls = recalls(in: context)
        return input
    }

    // MARK: - Tables

    private static func lessons(in context: NSManagedObjectContext) -> [CurriculumLessonRef] {
        let request = CDFetchRequest(CDLesson.self)
        request.fetchBatchSize = 200
        let fetched: [CDLesson] = context.safeFetch(request)
        return fetched.compactMap(lessonRef)
    }

    private static func lessonRef(_ lesson: CDLesson) -> CurriculumLessonRef? {
        guard let id: UUID = lesson.id else { return nil }
        let greatLessonRaw: String? = lesson.greatLessonRaw
        let taggedGreatLesson: String? = (greatLessonRaw?.isEmpty ?? true) ? nil : greatLessonRaw
        let isStory: Bool = lesson.lessonFormatRaw == LessonFormat.story.rawValue
        return CurriculumLessonRef(
            id: id,
            name: lesson.name,
            area: lesson.area.trimmed(),
            sequence: lesson.sequence.trimmed(),
            section: lesson.section.trimmed(),
            orderInSequence: Int(lesson.orderInSequence),
            sortIndex: Int(lesson.sortIndex),
            greatLessonRaw: taggedGreatLesson,
            isStory: isStory,
            isKeyLesson: lesson.isKeyLesson
        )
    }

    private static func students(in context: NSManagedObjectContext) -> [CurriculumStudentRef] {
        let request = CDFetchRequest(CDStudent.self)
        return context.safeFetch(request).compactMap { student in
            guard let id = student.id else { return nil }
            return CurriculumStudentRef(
                id: id,
                firstName: student.firstName,
                lastName: student.lastName,
                nickname: student.nickname.flatMap { $0.trimmed().isEmpty ? nil : $0 },
                levelRaw: student.levelRaw,
                dateStarted: student.dateStarted,
                isEnrolled: student.isEnrolled
            )
        }
    }

    /// Given presentations only; a plan that was never given is not evidence.
    private static func presentations(in context: NSManagedObjectContext) -> [CurriculumPresentationRef] {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "stateRaw == %@", LessonAssignmentState.presented.rawValue)
        request.fetchBatchSize = 200
        return context.safeFetch(request).compactMap { assignment in
            guard let id = assignment.id, let lessonID = assignment.lessonIDUUID else { return nil }
            return CurriculumPresentationRef(
                id: id,
                lessonID: lessonID,
                studentIDs: assignment.studentUUIDs,
                presentedAt: assignment.presentedAt,
                confirmedStudentIDs: assignment.confirmedStudentIDs.compactMap(UUID.init(uuidString:))
            )
        }
    }

    private static func masteries(in context: NSManagedObjectContext) -> [CurriculumMasteryRef] {
        let request = CDFetchRequest(CDLessonPresentation.self)
        request.fetchBatchSize = 200
        return context.safeFetch(request).compactMap { record in
            guard let id = record.id,
                  let studentID = UUID(uuidString: record.studentID),
                  let lessonID = UUID(uuidString: record.lessonID) else { return nil }
            // TrackProgressResolver's rule: a mastered date or the mastered state.
            let isMastered = record.masteredAt != nil || record.state == .proficient
            return CurriculumMasteryRef(
                id: id,
                studentID: studentID,
                lessonID: lessonID,
                isMastered: isMastered,
                presentedAt: record.presentedAt,
                masteredAt: record.masteredAt,
                lastObservedAt: record.lastObservedAt
            )
        }
    }

    private static func work(in context: NSManagedObjectContext) -> [CurriculumWorkRef] {
        let request = CDFetchRequest(CDWorkModel.self)
        request.fetchBatchSize = 200
        return context.safeFetch(request).compactMap { work in
            guard let id = work.id, let lessonID = UUID(uuidString: work.lessonID) else { return nil }
            let participants = (work.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []
            var studentIDs: [UUID] = participants.compactMap { UUID(uuidString: $0.studentID) }
            if let owner = UUID(uuidString: work.studentID), !studentIDs.contains(owner) {
                studentIDs.insert(owner, at: 0)
            }
            return CurriculumWorkRef(
                id: id,
                lessonID: lessonID,
                studentIDs: studentIDs,
                statusRaw: work.statusRaw,
                assignedAt: work.assignedAt ?? work.createdAt,
                completedAt: work.completedAt,
                lastTouchedAt: work.lastTouchedAt
            )
        }
    }

    private static func practice(in context: NSManagedObjectContext) -> [CurriculumPracticeRef] {
        let request = CDFetchRequest(CDPracticeSession.self)
        request.fetchBatchSize = 200
        return context.safeFetch(request).compactMap { session in
            guard let id = session.id else { return nil }
            return CurriculumPracticeRef(
                id: id,
                date: session.date,
                studentIDs: session.studentUUIDs,
                workIDs: session.workItemIDsArray.compactMap(UUID.init(uuidString:))
            )
        }
    }

    private static func recalls(in context: NSManagedObjectContext) -> [CurriculumRecallRef] {
        let request = CDFetchRequest(CDLessonRecallCheck.self)
        request.fetchBatchSize = 200
        return context.safeFetch(request).compactMap { check in
            guard let id = check.id,
                  let studentID = UUID(uuidString: check.studentID),
                  let lessonID = UUID(uuidString: check.lessonID) else { return nil }
            return CurriculumRecallRef(
                id: id,
                studentID: studentID,
                lessonID: lessonID,
                outcome: check.outcome,
                checkedAt: check.checkedAt
            )
        }
    }

    // MARK: - Change Detection

    /// Entities whose saves change what the grids show. Notes are deliberately
    /// absent: an observation attaches to a presentation but does not move a cell.
    static let watchedEntityNames: Set<String> = [
        "Lesson", "Student", "LessonAssignment", "LessonPresentation",
        "WorkModel", "WorkParticipantEntity", "PracticeSession", "LessonRecallCheck"
    ]
}
