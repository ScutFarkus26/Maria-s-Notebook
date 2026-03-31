// swiftlint:disable file_length
import Foundation
import CoreData
import OSLog

struct AvailableTrack {
    let subject: String
    let group: String
    let isSequential: Bool
}

/// Service for managing group-based tracks
@MainActor
// swiftlint:disable:next type_body_length
struct GroupTrackService {
    private static let logger = Logger.lessons

    // MARK: - Core Data API (Primary)

    /// Check if a group is marked as a track (Core Data)
    static func isTrack(
        subject: String,
        group: String,
        context: NSManagedObjectContext
    ) -> Bool {
        do {
            if let track = try cdGetGroupTrack(subject: subject, group: group, context: context) {
                return !track.isExplicitlyDisabled
            }
            return true
        } catch {
            return true
        }
    }

    /// Get GroupTrack for subject and group (Core Data)
    static func cdGetGroupTrack(
        subject: String,
        group: String,
        context: NSManagedObjectContext
    ) throws -> CDGroupTrackEntity? {
        let trimmedSubject = subject.trimmed()
        let trimmedGroup = group.trimmed()
        let allTracks = context.safeFetch(CDFetchRequest(CDGroupTrackEntity.self))
        return allTracks.first(where: { track in
            track.subject.trimmed().caseInsensitiveCompare(trimmedSubject) == .orderedSame &&
            track.group.trimmed().caseInsensitiveCompare(trimmedGroup) == .orderedSame
        })
    }

    /// Get or create a GroupTrack (Core Data)
    static func cdGetOrCreateGroupTrack(
        subject: String,
        group: String,
        context: NSManagedObjectContext
    ) throws -> CDGroupTrackEntity {
        let trimmedSubject = subject.trimmed()
        let trimmedGroup = group.trimmed()
        let allTracks = context.safeFetch(CDFetchRequest(CDGroupTrackEntity.self))
        if let existing = allTracks.first(where: { track in
            track.subject.trimmed().caseInsensitiveCompare(trimmedSubject) == .orderedSame &&
            track.group.trimmed().caseInsensitiveCompare(trimmedGroup) == .orderedSame
        }) {
            return existing
        }
        let newTrack = CDGroupTrackEntity(context: context)
        newTrack.subject = trimmedSubject
        newTrack.group = trimmedGroup
        newTrack.isSequential = true
        newTrack.isExplicitlyDisabled = false
        return newTrack
    }

    /// Find or create a Track object (Core Data)
    static func getOrCreateTrack(
        subject: String,
        group: String,
        context: NSManagedObjectContext
    ) throws -> CDTrackEntity {
        let trimmedSubject = subject.trimmed()
        let trimmedGroup = group.trimmed()

        guard isTrack(subject: trimmedSubject, group: trimmedGroup, context: context) else {
            throw NSError(
                domain: "GroupTrackService", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Group is explicitly disabled as a track"]
            )
        }

        let trackTitle = "\(trimmedSubject) — \(trimmedGroup)"
        let allTracks = context.safeFetch(CDFetchRequest(CDTrackEntity.self))

        if let existingTrack = allTracks.first(where: { $0.title.trimmed() == trackTitle }) {
            try cdEnsureTrackSteps(for: existingTrack, subject: trimmedSubject, group: trimmedGroup, context: context)
            return existingTrack
        }

        let newTrack = CDTrackEntity(context: context)
        newTrack.title = trackTitle
        try cdEnsureTrackSteps(for: newTrack, subject: trimmedSubject, group: trimmedGroup, context: context)
        return newTrack
    }

    /// Get Track object for a subject/group combination (Core Data)
    static func cdGetTrack(
        subject: String,
        group: String,
        context: NSManagedObjectContext
    ) throws -> CDTrackEntity? {
        let trimmedSubject = subject.trimmed()
        let trimmedGroup = group.trimmed()
        let trackTitle = "\(trimmedSubject) — \(trimmedGroup)"
        let allTracks = context.safeFetch(CDFetchRequest(CDTrackEntity.self))
        return allTracks.first(where: { $0.title.trimmed() == trackTitle })
    }

    /// Ensure TrackSteps exist for all lessons in a subject/group (Core Data)
    private static func cdEnsureTrackSteps(
        for track: CDTrackEntity,
        subject: String,
        group: String,
        context: NSManagedObjectContext
    ) throws {
        let allLessons = context.safeFetch(CDFetchRequest(CDLesson.self))
        let matchingLessons = allLessons.filter { lesson in
            lesson.subject.trimmed().caseInsensitiveCompare(subject) == .orderedSame &&
            lesson.group.trimmed().caseInsensitiveCompare(group) == .orderedSame
        }
        .sorted { Int($0.orderInGroup) < Int($1.orderInGroup) }

        let allSteps = context.safeFetch(CDFetchRequest(CDTrackStepEntity.self))
        let existingSteps = allSteps.filter { $0.track?.id == track.id }

        var existingStepsByLessonID: [UUID: CDTrackStepEntity] = [:]
        for step in existingSteps {
            if let lessonID = step.lessonTemplateID {
                existingStepsByLessonID[lessonID] = step
            }
        }

        var newSteps: [CDTrackStepEntity] = []
        for (index, lesson) in matchingLessons.enumerated() {
            guard let lessonID = lesson.id else { continue }
            if let existingStep = existingStepsByLessonID[lessonID] {
                existingStep.orderIndex = Int64(index)
                existingStep.track = track
                newSteps.append(existingStep)
            } else {
                let newStep = CDTrackStepEntity(context: context)
                newStep.track = track
                newStep.orderIndex = Int64(index)
                newStep.lessonTemplateID = lessonID
                newSteps.append(newStep)
            }
        }

        let existingLessonIDs = Set(matchingLessons.compactMap(\.id))
        for step in existingSteps {
            if let lessonID = step.lessonTemplateID, !existingLessonIDs.contains(lessonID) {
                context.delete(step)
            }
        }

        track.steps = NSSet(array: newSteps)
    }

    /// Auto-enroll students in a track if the lesson belongs to a track (Core Data)
    @MainActor static func autoEnrollInTrackIfNeeded(
        lessonSubject: String,
        lessonGroup: String,
        studentIDs: [String],
        context: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator? = nil
    ) {
        guard isTrack(subject: lessonSubject, group: lessonGroup, context: context) else {
            return
        }

        let track: CDTrackEntity
        do {
            track = try getOrCreateTrack(subject: lessonSubject, group: lessonGroup, context: context)
        } catch {
            logger.warning("Failed to get or create track during auto-enroll: \(error.localizedDescription)")
            return
        }

        let trackID = track.id?.uuidString ?? ""
        let allEnrollments = context.safeFetch(CDFetchRequest(CDStudentTrackEnrollmentEntity.self))

        for studentID in studentIDs {
            let existingEnrollment = allEnrollments.first { enrollment in
                enrollment.studentID == studentID && enrollment.trackID == trackID
            }

            if let existing = existingEnrollment {
                if !existing.isActive {
                    existing.isActive = true
                    if existing.startedAt == nil {
                        existing.startedAt = Date()
                    }
                }
            } else {
                let newEnrollment = CDStudentTrackEnrollmentEntity(context: context)
                newEnrollment.studentID = studentID
                newEnrollment.trackID = trackID
                newEnrollment.startedAt = Date()
                newEnrollment.isActive = true
            }
        }

        if let coordinator = saveCoordinator {
            coordinator.save(context, reason: "Auto-enrolling in track")
        } else {
            context.safeSave()
        }
    }

    /// Check if a track is complete for a student (Core Data)
    // swiftlint:disable:next function_body_length
    static func checkAndCompleteTrackIfNeeded(
        lessonSubject: String,
        lessonGroup: String,
        studentID: String,
        context: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator? = nil
    ) {
        guard isTrack(subject: lessonSubject, group: lessonGroup, context: context) else {
            return
        }

        let track: CDTrackEntity
        do {
            guard let fetchedTrack = try cdGetTrack(
                subject: lessonSubject, group: lessonGroup, context: context
            ) else {
                return
            }
            track = fetchedTrack
        } catch {
            logger.warning("Failed to get track for completion check: \(error.localizedDescription)")
            return
        }

        let allLessons = context.safeFetch(CDFetchRequest(CDLesson.self))
        let trackLessons = allLessons.filter { l in
            l.subject.trimmed().caseInsensitiveCompare(lessonSubject.trimmed()) == .orderedSame &&
            l.group.trimmed().caseInsensitiveCompare(lessonGroup.trimmed()) == .orderedSame
        }

        guard !trackLessons.isEmpty else { return }

        let allLessonPresentations = context.safeFetch(CDFetchRequest(CDLessonPresentation.self))
        let studentPresentations = allLessonPresentations.filter { $0.studentID == studentID }

        let trackLessonIDs = Set(trackLessons.compactMap { $0.id?.uuidString })
        let proficientLessonIDs = Set(studentPresentations
            .filter { $0.stateRaw == LessonPresentationState.proficient.rawValue && trackLessonIDs.contains($0.lessonID) }
            .map(\.lessonID))

        let allProficient = trackLessonIDs.isSubset(of: proficientLessonIDs)
        guard allProficient else { return }

        let trackID = track.id?.uuidString ?? ""
        let allEnrollments = context.safeFetch(CDFetchRequest(CDStudentTrackEnrollmentEntity.self))

        if let enrollment = allEnrollments.first(where: {
            $0.studentID == studentID && $0.trackID == trackID && $0.isActive
        }) {
            enrollment.isActive = false
            if let coordinator = saveCoordinator {
                coordinator.save(context, reason: "Completing track enrollment")
            } else {
                context.safeSave()
            }
        }
    }

    /// Returns all lessons matching the group track's subject and group, sorted by order.
    static func getLessonsForTrack(track: CDGroupTrackEntity, allLessons: [CDLesson]) -> [CDLesson] {
        allLessons.filter { lesson in
            lesson.subject.trimmed().caseInsensitiveCompare(track.subject.trimmed()) == .orderedSame &&
            lesson.group.trimmed().caseInsensitiveCompare(track.group.trimmed()) == .orderedSame
        }
        .sorted { Int($0.orderInGroup) < Int($1.orderInGroup) }
    }
}
