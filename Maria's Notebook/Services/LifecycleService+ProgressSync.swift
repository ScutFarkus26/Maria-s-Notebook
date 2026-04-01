import Foundation
import CoreData
import os

// MARK: - Progress Synchronization

extension LifecycleService {

    /// Synchronizes student progress by updating CDLessonPresentation records from CDLessonAssignment and CDWorkModel data.
    /// This ensures all presented/completed lessons are properly tracked in the progress system.
    /// - Parameters:
    ///   - context: The NSManagedObjectContext to operate on
    /// - Returns: A tuple with counts of (presentations created/updated, presentations marked as proficient)
    static func syncAllStudentProgress(context: NSManagedObjectContext) throws -> (presentationsUpdated: Int, proficient: Int) {
        // 1. Fetch presented lesson assignments
        let presentedRaw = LessonAssignmentState.presented.rawValue
        let laRequest = CDFetchRequest(CDLessonAssignment.self)
        laRequest.predicate = NSPredicate(format: "stateRaw == %@", presentedRaw)
        let allLessonAssignments = try context.fetch(laRequest)

        // 2. Fetch students for orphan cleaning
        let allStudents = try context.fetch(CDFetchRequest(CDStudent.self))
        let validStudentIDs = Set(allStudents.compactMap { $0.id?.uuidString })

        // 3. Build lesson lookup (deduplication: CloudKit sync can create duplicate records)
        let allLessons = try context.fetch(CDFetchRequest(CDLesson.self))
        let lessonsByID = Dictionary(
            allLessons.compactMap { lesson -> (String, CDLesson)? in
                guard let id = lesson.id?.uuidString else { return nil }
                return (id, lesson)
            },
            uniquingKeysWith: { first, _ in first }
        )

        // 4. Create GroupTracks for all subject/group combinations
        try createGroupTracks(from: allLessons, context: context)

        // 5. Sync presentations per assignment
        var presentationsUpdated = 0
        for la in allLessonAssignments {
            presentationsUpdated += try syncPresentationsForAssignment(
                la, lessonsByID: lessonsByID, validStudentIDs: validStudentIDs, context: context
            )
        }

        // 6. Save and check work completion
        try context.save()
        let allWorkModels = try context.fetch(CDFetchRequest(CDWorkModel.self))
        let allLessonPresentations = try context.fetch(CDFetchRequest(CDLessonPresentation.self))
        let proficientCount = updateCompletionFromWorkModels(
            allWorkModels, allLessonAssignments: allLessonAssignments,
            allLessonPresentations: allLessonPresentations
        )

        try context.save()
        return (presentationsUpdated, proficientCount)
    }

    // MARK: - Phase Helpers

    /// Creates CDGroupTrackEntity records for all unique subject/group combinations found in lessons.
    private static func createGroupTracks(from allLessons: [CDLesson], context: NSManagedObjectContext) throws {
        var uniqueSubjectGroups: Set<String> = []
        for lesson in allLessons {
            let subject = lesson.subject.trimmed()
            let group = lesson.group.trimmed()
            guard !subject.isEmpty && !group.isEmpty else { continue }

            let key = "\(subject)|\(group)"
            guard !uniqueSubjectGroups.contains(key) else { continue }
            uniqueSubjectGroups.insert(key)

            if GroupTrackService.isTrack(subject: subject, group: group, context: context) {
                do {
                    _ = try GroupTrackService.cdGetOrCreateGroupTrack(
                        subject: subject,
                        group: group,
                        context: context
                    )
                } catch {
                    // swiftlint:disable:next line_length
                    logger.warning("Failed to create/get CDGroupTrackEntity for \(subject, privacy: .public)/\(group, privacy: .public): \(error.localizedDescription)")
                }
            }
        }
        try context.save()
    }

    /// Syncs CDLessonPresentation records for a single CDLessonAssignment, including track enrollment.
    /// Returns the number of presentation records updated.
    private static func syncPresentationsForAssignment(
        _ la: CDLessonAssignment,
        lessonsByID: [String: CDLesson],
        validStudentIDs: Set<String>,
        context: NSManagedObjectContext
    ) throws -> Int {
        var updated = 0

        // Clean orphaned IDs
        cleanOrphanedStudentIDs(for: la, validStudentIDs: validStudentIDs, modelContext: context)

        // Skip if no valid students or invalid lessonID
        guard !la.studentIDs.isEmpty,
              !la.lessonID.isEmpty,
              UUID(uuidString: la.lessonID) != nil else { return 0 }

        let presentedAt = la.presentedAt ?? la.createdAt ?? Date()

        // Get lesson - try relationship first, then lookup
        let lesson: CDLesson?
        if let relationshipLesson = la.lesson {
            lesson = relationshipLesson
        } else {
            lesson = lessonsByID[la.lessonID]
        }

        guard lesson != nil else {
            // swiftlint:disable:next line_length
            logger.warning("Skipping CDLessonAssignment \(la.id?.uuidString ?? "nil", privacy: .public): lesson not found for lessonID \(la.lessonID, privacy: .public)")
            return 0
        }

        updated += try recordPresentationWithFallback(la, lesson: lesson, presentedAt: presentedAt, context: context)

        if let lesson {
            try enrollInTrackIfNeeded(
                lesson: lesson, studentIDs: la.studentIDs, lessonID: la.lessonID, context: context
            )
        }

        return updated
    }

    /// Records presentation and updates presentationIDs; falls back to direct upsert on failure.
    private static func recordPresentationWithFallback(
        _ la: CDLessonAssignment, lesson: CDLesson?, presentedAt: Date, context: NSManagedObjectContext
    ) throws -> Int {
        do {
            if la.lesson == nil, let lesson {
                la.lesson = lesson
            }
            let (updatedLA, _) = try recordPresentationAndExplodeWork(
                from: la, presentedAt: presentedAt, modelContext: context
            )
            let assignmentIDStr = updatedLA.id?.uuidString ?? ""
            let allLessonPresentations = try context.fetch(CDFetchRequest(CDLessonPresentation.self))
            for studentIDStr in la.studentIDs {
                if let lp = allLessonPresentations.first(where: {
                    $0.lessonID == la.lessonID && $0.studentID == studentIDStr && $0.presentationID == nil
                }) {
                    lp.presentationID = assignmentIDStr
                }
            }
            return la.studentIDs.count
        } catch {
            // swiftlint:disable:next line_length
            logger.warning("Failed to process CDLessonAssignment \(la.id?.uuidString ?? "nil", privacy: .public): \(error.localizedDescription)")
            for studentIDStr in la.studentIDs {
                try upsertLessonPresentationByLessonAndStudent(
                    lessonID: la.lessonID, studentID: studentIDStr, presentedAt: presentedAt, context: context
                )
            }
            return la.studentIDs.count
        }
    }

    /// Auto-enrolls students in a track if the lesson belongs to one, and stamps trackID on presentations.
    private static func enrollInTrackIfNeeded(
        lesson: CDLesson, studentIDs: [String], lessonID: String, context: NSManagedObjectContext
    ) throws {
        let subject = lesson.subject.trimmed()
        let group = lesson.group.trimmed()
        guard !subject.isEmpty && !group.isEmpty else { return }
        guard GroupTrackService.isTrack(subject: subject, group: group, context: context) else { return }

        do {
            _ = try GroupTrackService.getOrCreateTrack(subject: subject, group: group, context: context)
        } catch {
            // swiftlint:disable:next line_length
            logger.warning("Failed to create/get CDGroupTrackEntity for \(subject, privacy: .public)/\(group, privacy: .public): \(error.localizedDescription)")
        }

        GroupTrackService.autoEnrollInTrackIfNeeded(
            lessonSubject: subject, lessonGroup: group, studentIDs: studentIDs, context: context
        )

        let trackID = "\(subject)|\(group)"
        let presentations = safeFetch(
            CDFetchRequest(CDLessonPresentation.self), using: context, caller: "syncAllStudentProgress"
        )
        for studentIDStr in studentIDs {
            if let lp = presentations.first(where: { $0.lessonID == lessonID && $0.studentID == studentIDStr }) {
                if lp.trackID != trackID { lp.trackID = trackID }
            }
        }
    }

    /// Checks CDWorkModel completion status and updates proficiency on matching CDLessonPresentation records.
    /// Returns the number of newly proficient records.
    private static func updateCompletionFromWorkModels(
        _ allWorkModels: [CDWorkModel],
        allLessonAssignments: [CDLessonAssignment],
        allLessonPresentations: [CDLessonPresentation]
    ) -> Int {
        var proficientCount = 0

        for work in allWorkModels {
            let isWorkCompleted = work.status == .complete || work.completedAt != nil

            guard let workPresentationID = work.presentationID else { continue }
            guard let la = allLessonAssignments.first(where: { $0.id?.uuidString == workPresentationID }) else {
                continue
            }

            let lessonIDStr = la.lessonID
            let participants = (work.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []

            if participants.isEmpty {
                if isWorkCompleted {
                    for studentIDStr in la.studentIDs {
                        proficientCount += markProficientIfNeeded(
                            lessonID: lessonIDStr, studentID: studentIDStr,
                            achievedAt: work.completedAt ?? work.lastTouchedAt ?? Date(),
                            in: allLessonPresentations
                        )
                    }
                }
            } else {
                for participant in participants {
                    let studentIDStr = participant.studentID
                    guard !studentIDStr.isEmpty else { continue }

                    let isParticipantCompleted = participant.completedAt != nil || isWorkCompleted
                    if isParticipantCompleted {
                        proficientCount += markProficientIfNeeded(
                            lessonID: lessonIDStr, studentID: studentIDStr,
                            achievedAt: participant.completedAt
                                ?? work.completedAt ?? work.lastTouchedAt ?? Date(),
                            in: allLessonPresentations
                        )
                    }
                }
            }
        }

        return proficientCount
    }

    /// Marks a single CDLessonPresentation as proficient if not already. Returns 1 if updated, 0 otherwise.
    private static func markProficientIfNeeded(
        lessonID: String, studentID: String, achievedAt: Date,
        in presentations: [CDLessonPresentation]
    ) -> Int {
        if let lp = presentations.first(where: {
            $0.lessonID == lessonID && $0.studentID == studentID
        }) {
            if lp.state != .proficient || lp.masteredAt == nil {
                lp.state = .proficient
                lp.masteredAt = achievedAt
                return 1
            }
        }
        return 0
    }
}
