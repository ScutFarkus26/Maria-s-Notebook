import Foundation
import CoreData
import OSLog

/// Service for managing sequence-based tracks
@MainActor
// swiftlint:disable:next type_body_length
struct SequenceTrackService {
    private static let logger = Logger.lessons

    // MARK: - Shared-store guard

    /// True when the context is backed by a two-store CloudKit configuration
    /// (i.e. there's a store assigned to `CoreDataStack.sharedConfiguration`)
    /// AND no CKShare exists yet. Writing shared-store entities in this state
    /// creates orphan records that poison the CloudKit mirroring delegate
    /// with NSCocoaErrorDomain 134060. Returns `false` for local-only and
    /// in-memory test stacks (single unified store, no shared configuration).
    static func shouldDeferSharedStoreWrites(context: NSManagedObjectContext) -> Bool {
        let stores = context.persistentStoreCoordinator?.persistentStores ?? []
        let hasSharedStore = stores.contains { $0.configurationName == CoreDataStack.sharedConfiguration }
        return hasSharedStore && !SharedStoreZoneRepair.shared.hasActiveShare
    }

    // MARK: - Core Data API (Primary)

    /// Check if a sequence is marked as a track (Core Data)
    static func isTrack(
        area: String,
        sequence: String,
        context: NSManagedObjectContext
    ) -> Bool {
        do {
            if let track = try cdGetSequenceTrack(area: area, sequence: sequence, context: context) {
                return !track.isExplicitlyDisabled
            }
            return true
        } catch {
            return true
        }
    }

    /// Get CDSequenceTrackEntity for area and sequence (Core Data)
    static func cdGetSequenceTrack(
        area: String,
        sequence: String,
        context: NSManagedObjectContext
    ) throws -> CDSequenceTrackEntity? {
        let trimmedArea = area.trimmed()
        let trimmedSequence = sequence.trimmed()
        let allTracks = context.safeFetch(CDFetchRequest(CDSequenceTrackEntity.self))
        return allTracks.first(where: { track in
            track.area.trimmed().caseInsensitiveCompare(trimmedArea) == .orderedSame &&
            track.sequence.trimmed().caseInsensitiveCompare(trimmedSequence) == .orderedSame
        })
    }

    /// Get or create a CDSequenceTrackEntity (Core Data)
    static func cdGetOrCreateSequenceTrack(
        area: String,
        sequence: String,
        context: NSManagedObjectContext
    ) throws -> CDSequenceTrackEntity {
        let trimmedArea = area.trimmed()
        let trimmedSequence = sequence.trimmed()
        let allTracks = context.safeFetch(CDFetchRequest(CDSequenceTrackEntity.self))
        if let existing = allTracks.first(where: { track in
            track.area.trimmed().caseInsensitiveCompare(trimmedArea) == .orderedSame &&
            track.sequence.trimmed().caseInsensitiveCompare(trimmedSequence) == .orderedSame
        }) {
            return existing
        }
        let newSequenceTrack = CDSequenceTrackEntity(context: context)
        newSequenceTrack.area = trimmedArea
        newSequenceTrack.sequence = trimmedSequence
        newSequenceTrack.isSequential = true
        newSequenceTrack.isExplicitlyDisabled = false
        return newSequenceTrack
    }

    /// Find or create a CDTrackEntity object (Core Data)
    static func getOrCreateTrack(
        area: String,
        sequence: String,
        context: NSManagedObjectContext
    ) throws -> CDTrackEntity {
        let trimmedArea = area.trimmed()
        let trimmedSequence = sequence.trimmed()

        guard isTrack(area: trimmedArea, sequence: trimmedSequence, context: context) else {
            throw NSError(
                domain: "SequenceTrackService", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Group is explicitly disabled as a track"]
            )
        }

        let trackTitle = "\(trimmedArea) — \(trimmedSequence)"
        let allTracks = context.safeFetch(CDFetchRequest(CDTrackEntity.self))

        let sequenceTrack = try? cdGetSequenceTrack(area: trimmedArea, sequence: trimmedSequence, context: context)

        if let existingTrack = allTracks.first(where: { $0.title.trimmed() == trackTitle }) {
            if existingTrack.sequenceTrack == nil, let sequenceTrack {
                existingTrack.sequenceTrack = sequenceTrack
            }
            try cdEnsureTrackSteps(for: existingTrack, area: trimmedArea, sequence: trimmedSequence, context: context)
            return existingTrack
        }

        // CDTrackEntity is a shared-store entity. In the two-store CloudKit
        // configuration, creating it before any CKShare exists produces orphan
        // records that poison the CloudKit mirroring delegate
        // (NSCocoaErrorDomain 134060). All call sites already wrap this in
        // try/catch and treat track creation as best-effort, so throw here
        // and let them no-op until a share is in place. Local-only / test
        // stacks have no shared-configured store, so the gate is skipped
        // there.
        if shouldDeferSharedStoreWrites(context: context) {
            throw NSError(
                domain: "SequenceTrackService", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Cannot create track before classroom CKShare exists"]
            )
        }

        let newTrack = CDTrackEntity(context: context)
        newTrack.title = trackTitle
        newTrack.sequenceTrack = sequenceTrack
        try cdEnsureTrackSteps(for: newTrack, area: trimmedArea, sequence: trimmedSequence, context: context)
        return newTrack
    }

    /// Get CDTrackEntity object for a area/sequence combination (Core Data)
    static func cdGetTrack(
        area: String,
        sequence: String,
        context: NSManagedObjectContext
    ) throws -> CDTrackEntity? {
        let trimmedArea = area.trimmed()
        let trimmedSequence = sequence.trimmed()
        let trackTitle = "\(trimmedArea) — \(trimmedSequence)"
        let allTracks = context.safeFetch(CDFetchRequest(CDTrackEntity.self))
        return allTracks.first(where: { $0.title.trimmed() == trackTitle })
    }

    /// Ensure TrackSteps exist for all lessons in a area/sequence (Core Data)
    private static func cdEnsureTrackSteps(
        for track: CDTrackEntity,
        area: String,
        sequence: String,
        context: NSManagedObjectContext
    ) throws {
        // CDTrackStepEntity is a shared-store entity. In the two-store
        // CloudKit configuration, skip creation until a CKShare exists —
        // otherwise the new step records become orphans that poison the
        // CloudKit mirroring delegate (NSCocoaErrorDomain 134060). Steps
        // get back-filled by the auto-create-share path or the orphan-guard
        // observer the next time getOrCreateTrack runs after a share is in
        // place. Local-only / test stacks have no shared-configured store,
        // so the gate is skipped there.
        guard !shouldDeferSharedStoreWrites(context: context) else { return }

        let allLessons = context.safeFetch(CDFetchRequest(CDLesson.self))
        let matchingLessons = allLessons.filter { lesson in
            lesson.area.trimmed().caseInsensitiveCompare(area) == .orderedSame &&
            lesson.sequence.trimmed().caseInsensitiveCompare(sequence) == .orderedSame
        }
        .sorted { Int($0.orderInSequence) < Int($1.orderInSequence) }

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
    @discardableResult
    static func autoEnrollInTrackIfNeeded(
        lessonArea: String,
        lessonSequence: String,
        studentIDs: [String],
        context: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator? = nil
    ) -> String? {
        performAutoEnrollment(
            lessonArea: lessonArea,
            lessonSequence: lessonSequence,
            studentIDs: studentIDs,
            context: context,
            persistence: saveCoordinator.map(EnrollmentPersistence.coordinator) ?? .context
        )
    }

    /// Variant for a caller that owns a larger atomic Core Data save.
    @discardableResult
    static func autoEnrollInTrackIfNeeded(
        lessonArea: String,
        lessonSequence: String,
        studentIDs: [String],
        context: NSManagedObjectContext,
        saveChanges: Bool
    ) -> String? {
        performAutoEnrollment(
            lessonArea: lessonArea,
            lessonSequence: lessonSequence,
            studentIDs: studentIDs,
            context: context,
            persistence: saveChanges ? .context : .deferred
        )
    }

    private static func performAutoEnrollment(
        lessonArea: String,
        lessonSequence: String,
        studentIDs: [String],
        context: NSManagedObjectContext,
        persistence: EnrollmentPersistence
    ) -> String? {
        guard isTrack(area: lessonArea, sequence: lessonSequence, context: context) else {
            return nil
        }

        let track: CDTrackEntity
        do {
            track = try getOrCreateTrack(area: lessonArea, sequence: lessonSequence, context: context)
        } catch {
            logger.warning("Failed to get or create track during auto-enroll: \(error.localizedDescription)")
            return nil
        }

        let trackID = track.id?.uuidString ?? ""
        let allEnrollments = context.safeFetch(CDFetchRequest(CDStudentTrackEnrollmentEntity.self))
        let allStudents = context.safeFetch(CDFetchRequest(CDStudent.self))

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
                // Backfill relationships if missing
                if existing.track == nil { existing.track = track }
                if existing.student == nil {
                    existing.student = allStudents.first { $0.id?.uuidString == studentID }
                }
            } else {
                let newEnrollment = CDStudentTrackEnrollmentEntity(context: context)
                newEnrollment.studentID = studentID
                newEnrollment.trackID = trackID
                newEnrollment.startedAt = Date()
                newEnrollment.isActive = true
                newEnrollment.track = track
                newEnrollment.student = allStudents.first { $0.id?.uuidString == studentID }
            }
        }

        persistEnrollmentChanges(persistence, in: context)
        return trackID
    }

    private static func persistEnrollmentChanges(
        _ persistence: EnrollmentPersistence,
        in context: NSManagedObjectContext
    ) {
        switch persistence {
        case .context:
            context.safeSave()
        case .coordinator(let coordinator):
            coordinator.save(context, reason: "Auto-enrolling in track")
        case .deferred:
            break
        }
    }

    private enum EnrollmentPersistence {
        case context
        case coordinator(SaveCoordinator)
        case deferred
    }

    /// Check if a track is complete for a student (Core Data)
    static func checkAndCompleteTrackIfNeeded(
        lessonArea: String,
        lessonSequence: String,
        studentID: String,
        context: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator? = nil
    ) {
        guard isTrack(area: lessonArea, sequence: lessonSequence, context: context) else {
            return
        }

        let track: CDTrackEntity
        do {
            guard let fetchedTrack = try cdGetTrack(
                area: lessonArea, sequence: lessonSequence, context: context
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
            l.area.trimmed().caseInsensitiveCompare(lessonArea.trimmed()) == .orderedSame &&
            l.sequence.trimmed().caseInsensitiveCompare(lessonSequence.trimmed()) == .orderedSame
        }

        guard !trackLessons.isEmpty else { return }

        let allLessonPresentations = context.safeFetch(CDFetchRequest(CDLessonPresentation.self))
        let studentPresentations = allLessonPresentations.filter { $0.studentID == studentID }

        let trackLessonIDs = Set(trackLessons.compactMap { $0.id?.uuidString })
        let proficientLessonIDs = Set(studentPresentations
            .filter {
                $0.stateRaw == LessonPresentationState.proficient.rawValue
                    && trackLessonIDs.contains($0.lessonID)
            }
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

    /// Returns all lessons matching the sequence track's area and sequence, sorted by order.
    static func getLessonsForTrack(track: CDSequenceTrackEntity, allLessons: [CDLesson]) -> [CDLesson] {
        allLessons.filter { lesson in
            lesson.area.trimmed().caseInsensitiveCompare(track.area.trimmed()) == .orderedSame &&
            lesson.sequence.trimmed().caseInsensitiveCompare(track.sequence.trimmed()) == .orderedSame
        }
        .sorted { Int($0.orderInSequence) < Int($1.orderInSequence) }
    }
}
