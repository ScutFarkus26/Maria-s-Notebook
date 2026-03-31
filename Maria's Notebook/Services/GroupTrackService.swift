// swiftlint:disable file_length
import Foundation
import SwiftData
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

    // MARK: - SwiftData API (Deprecated — migrate callers to Core Data in Phase 4)

    @available(*, deprecated, message: "Use Core Data context: overload")
    private static func safeFetch<T>(
        _ descriptor: FetchDescriptor<T>,
        modelContext: ModelContext,
        context: String = #function
    ) -> [T] {
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            logger.warning("Failed to fetch \(T.self, privacy: .public): \(error.localizedDescription)")
            return []
        }
    }

    @available(*, deprecated, message: "Use Core Data context: overload")
    private static func safeSave(modelContext: ModelContext, context: String = #function) {
        do {
            try modelContext.save()
        } catch {
            logger.warning("Failed to save: \(error.localizedDescription)")
        }
    }

    @available(*, deprecated, message: "Use cdGetOrCreateGroupTrack(subject:group:context:)")
    static func getOrCreateGroupTrack(
        subject: String,
        group: String,
        modelContext: ModelContext
    ) throws -> GroupTrack {
        let trimmedSubject = subject.trimmed()
        let trimmedGroup = group.trimmed()
        let allTracks = try modelContext.fetch(FetchDescriptor<GroupTrack>())
        if let existing = allTracks.first(where: { track in
            track.subject.trimmed().caseInsensitiveCompare(trimmedSubject) == .orderedSame &&
            track.group.trimmed().caseInsensitiveCompare(trimmedGroup) == .orderedSame
        }) {
            return existing
        }
        let newTrack = GroupTrack(
            subject: trimmedSubject, group: trimmedGroup,
            isSequential: true, isExplicitlyDisabled: false
        )
        modelContext.insert(newTrack)
        return newTrack
    }

    @available(*, deprecated, message: "Use cdGetGroupTrack(subject:group:context:)")
    static func getGroupTrack(
        subject: String,
        group: String,
        modelContext: ModelContext
    ) throws -> GroupTrack? {
        let trimmedSubject = subject.trimmed()
        let trimmedGroup = group.trimmed()
        let allTracks = try modelContext.fetch(FetchDescriptor<GroupTrack>())
        return allTracks.first(where: { track in
            track.subject.trimmed().caseInsensitiveCompare(trimmedSubject) == .orderedSame &&
            track.group.trimmed().caseInsensitiveCompare(trimmedGroup) == .orderedSame
        })
    }

    @available(*, deprecated, message: "Use Core Data context: overload")
    static func getEffectiveTrackSettings(
        subject: String,
        group: String,
        modelContext: ModelContext
    ) throws -> (isSequential: Bool, isExplicitlyDisabled: Bool) {
        if let track = try getGroupTrack(subject: subject, group: group, modelContext: modelContext) {
            return (isSequential: track.isSequential, isExplicitlyDisabled: track.isExplicitlyDisabled)
        }
        return (isSequential: true, isExplicitlyDisabled: false)
    }

    @available(*, deprecated, message: "Use isTrack(subject:group:context:)")
    static func isTrack(
        subject: String,
        group: String,
        modelContext: ModelContext
    ) -> Bool {
        do {
            if let track = try getGroupTrack(subject: subject, group: group, modelContext: modelContext) {
                return !track.isExplicitlyDisabled
            }
            return true
        } catch {
            return true
        }
    }

    @available(*, deprecated, message: "Use Core Data context: overload")
    static func removeTrack(
        subject: String,
        group: String,
        modelContext: ModelContext
    ) throws {
        if let track = try getGroupTrack(subject: subject, group: group, modelContext: modelContext) {
            track.isExplicitlyDisabled = true
        } else {
            let disabledTrack = GroupTrack(
                subject: subject.trimmed(), group: group.trimmed(),
                isSequential: true, isExplicitlyDisabled: true
            )
            modelContext.insert(disabledTrack)
        }
    }

    @available(*, deprecated, message: "Use Core Data context: overload")
    static func getAllGroupTracks(modelContext: ModelContext) throws -> [GroupTrack] {
        return try modelContext.fetch(FetchDescriptor<GroupTrack>(
            sortBy: [SortDescriptor(\.subject), SortDescriptor(\.group)]
        ))
    }

    @available(*, deprecated, message: "Use Core Data context: overload")
    static func getAllAvailableTracks(
        from lessons: [Lesson],
        modelContext: ModelContext
    ) throws -> [AvailableTrack] {
        let allTracks = try modelContext.fetch(FetchDescriptor<GroupTrack>())
        let tracksByKey: [String: GroupTrack] = Dictionary(
            allTracks.map { track in
                let key = "\(track.subject.trimmed().lowercased())|\(track.group.trimmed().lowercased())"
                return (key, track)
            },
            uniquingKeysWith: { first, _ in first }
        )

        func isTrackCached(subject: String, group: String) -> Bool {
            let key = "\(subject.trimmed().lowercased())|\(group.trimmed().lowercased())"
            if let track = tracksByKey[key] { return !track.isExplicitlyDisabled }
            return true
        }

        func getSettingsCached(subject: String, group: String) -> (isSequential: Bool, isExplicitlyDisabled: Bool) {
            let key = "\(subject.trimmed().lowercased())|\(group.trimmed().lowercased())"
            if let track = tracksByKey[key] {
                return (isSequential: track.isSequential, isExplicitlyDisabled: track.isExplicitlyDisabled)
            }
            return (isSequential: true, isExplicitlyDisabled: false)
        }

        var uniqueGroupsDict: [String: (subject: String, group: String)] = [:]
        for lesson in lessons {
            let subject = lesson.subject.trimmed()
            let group = lesson.group.trimmed()
            guard !subject.isEmpty && !group.isEmpty else { continue }
            let key = "\(subject)|\(group)"
            if uniqueGroupsDict[key] == nil {
                uniqueGroupsDict[key] = (subject: subject, group: group)
            }
        }

        var availableTracks: [AvailableTrack] = []
        for (subject, group) in uniqueGroupsDict.values {
            guard isTrackCached(subject: subject, group: group) else { continue }
            let settings = getSettingsCached(subject: subject, group: group)
            availableTracks.append(AvailableTrack(subject: subject, group: group, isSequential: settings.isSequential))
        }

        return availableTracks.sorted { lhs, rhs in
            if lhs.subject != rhs.subject {
                return lhs.subject.localizedCaseInsensitiveCompare(rhs.subject) == .orderedAscending
            }
            return lhs.group.localizedCaseInsensitiveCompare(rhs.group) == .orderedAscending
        }
    }

    @available(*, deprecated, message: "Use Core Data context: overload")
    static func getLessonsForTrack(
        track: GroupTrack,
        allLessons: [Lesson]
    ) -> [Lesson] {
        return allLessons
            .filter { lesson in
                lesson.subject.trimmed().caseInsensitiveCompare(track.subject.trimmed()) == .orderedSame &&
                lesson.group.trimmed().caseInsensitiveCompare(track.group.trimmed()) == .orderedSame
            }
            .sorted { lhs, rhs in
                if track.isSequential {
                    if lhs.orderInGroup != rhs.orderInGroup {
                        return lhs.orderInGroup < rhs.orderInGroup
                    }
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    @available(*, deprecated, message: "Use getOrCreateTrack(subject:group:context:)")
    static func getOrCreateTrack(
        subject: String,
        group: String,
        modelContext: ModelContext
    ) throws -> Track {
        let trimmedSubject = subject.trimmed()
        let trimmedGroup = group.trimmed()

        guard isTrack(subject: trimmedSubject, group: trimmedGroup, modelContext: modelContext) else {
            throw NSError(
                domain: "GroupTrackService", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Group is explicitly disabled as a track"]
            )
        }

        let trackTitle = "\(trimmedSubject) — \(trimmedGroup)"
        let allTracks = try modelContext.fetch(FetchDescriptor<Track>())

        if let existingTrack = allTracks.first(where: { $0.title.trimmed() == trackTitle }) {
            try ensureTrackSteps(for: existingTrack, subject: trimmedSubject, group: trimmedGroup, modelContext: modelContext)
            return existingTrack
        }

        let newTrack = Track(title: trackTitle, createdAt: Date())
        modelContext.insert(newTrack)
        try ensureTrackSteps(for: newTrack, subject: trimmedSubject, group: trimmedGroup, modelContext: modelContext)
        return newTrack
    }

    @available(*, deprecated, message: "Use Core Data version")
    private static func ensureTrackSteps(
        for track: Track,
        subject: String,
        group: String,
        modelContext: ModelContext
    ) throws {
        let allLessons = try modelContext.fetch(FetchDescriptor<Lesson>())
        let matchingLessons = allLessons.filter { lesson in
            lesson.subject.trimmed().caseInsensitiveCompare(subject) == .orderedSame &&
            lesson.group.trimmed().caseInsensitiveCompare(group) == .orderedSame
        }
        .sorted { $0.orderInGroup < $1.orderInGroup }

        let allSteps = try modelContext.fetch(FetchDescriptor<TrackStep>())
        let existingSteps = allSteps.filter { $0.track?.id == track.id }

        var existingStepsByLessonID: [UUID: TrackStep] = [:]
        for step in existingSteps {
            if let lessonID = step.lessonTemplateID {
                existingStepsByLessonID[lessonID] = step
            }
        }

        var steps: [TrackStep] = []
        for (index, lesson) in matchingLessons.enumerated() {
            if let existingStep = existingStepsByLessonID[lesson.id] {
                existingStep.orderIndex = index
                existingStep.track = track
                steps.append(existingStep)
            } else {
                let newStep = TrackStep(track: track, orderIndex: index, lessonTemplateID: lesson.id, createdAt: Date())
                modelContext.insert(newStep)
                steps.append(newStep)
            }
        }

        let existingLessonIDs = Set(matchingLessons.map(\.id))
        for step in existingSteps {
            if let lessonID = step.lessonTemplateID, !existingLessonIDs.contains(lessonID) {
                modelContext.delete(step)
            }
        }
        track.steps = steps
    }

    @available(*, deprecated, message: "Use Core Data version")
    static func getTrack(
        subject: String,
        group: String,
        modelContext: ModelContext
    ) throws -> Track? {
        let trimmedSubject = subject.trimmed()
        let trimmedGroup = group.trimmed()
        let trackTitle = "\(trimmedSubject) — \(trimmedGroup)"
        let allTracks = try modelContext.fetch(FetchDescriptor<Track>())
        return allTracks.first(where: { $0.title.trimmed() == trackTitle })
    }

    @available(*, deprecated, message: "Use autoEnrollInTrackIfNeeded(lessonSubject:lessonGroup:studentIDs:context:saveCoordinator:)")
    @MainActor static func autoEnrollInTrackIfNeeded(
        lesson: Lesson,
        studentIDs: [String],
        modelContext: ModelContext,
        saveCoordinator: SaveCoordinator? = nil
    ) {
        guard isTrack(subject: lesson.subject, group: lesson.group, modelContext: modelContext) else {
            return
        }

        let track: Track
        do {
            track = try getOrCreateTrack(subject: lesson.subject, group: lesson.group, modelContext: modelContext)
        } catch {
            logger.warning("Failed to get or create track during auto-enroll: \(error.localizedDescription)")
            return
        }

        let trackID = track.id.uuidString
        let allEnrollments = safeFetch(
            FetchDescriptor<StudentTrackEnrollment>(), modelContext: modelContext,
            context: "autoEnrollInTrackIfNeeded"
        )

        for studentID in studentIDs {
            let existingEnrollment = allEnrollments.first { $0.studentID == studentID && $0.trackID == trackID }
            if let existing = existingEnrollment {
                if !existing.isActive {
                    existing.isActive = true
                    if existing.startedAt == nil { existing.startedAt = Date() }
                }
            } else {
                let newEnrollment = StudentTrackEnrollment(
                    studentID: studentID, trackID: trackID, startedAt: Date(), isActive: true
                )
                modelContext.insert(newEnrollment)
            }
        }

        if let coordinator = saveCoordinator {
            coordinator.save(modelContext, reason: "Auto-enrolling in track")
        } else {
            safeSave(modelContext: modelContext, context: "autoEnrollInTrackIfNeeded")
        }
    }

    @available(*, deprecated, message: "Use checkAndCompleteTrackIfNeeded(lessonSubject:lessonGroup:studentID:context:saveCoordinator:)")
    // swiftlint:disable:next function_body_length
    static func checkAndCompleteTrackIfNeeded(
        lesson: Lesson,
        studentID: String,
        modelContext: ModelContext,
        saveCoordinator: SaveCoordinator? = nil
    ) {
        guard isTrack(subject: lesson.subject, group: lesson.group, modelContext: modelContext) else {
            return
        }

        let track: Track
        do {
            guard let fetchedTrack = try getTrack(
                subject: lesson.subject, group: lesson.group, modelContext: modelContext
            ) else { return }
            track = fetchedTrack
        } catch {
            logger.warning("Failed to get track for completion check: \(error.localizedDescription)")
            return
        }

        let allLessons = safeFetch(FetchDescriptor<Lesson>(), modelContext: modelContext, context: "checkAndCompleteTrackIfNeeded")
        let trackLessons = allLessons.filter { l in
            l.subject.trimmed().caseInsensitiveCompare(lesson.subject.trimmed()) == .orderedSame &&
            l.group.trimmed().caseInsensitiveCompare(lesson.group.trimmed()) == .orderedSame
        }
        guard !trackLessons.isEmpty else { return }

        let allLessonPresentations = safeFetch(
            FetchDescriptor<LessonPresentation>(), modelContext: modelContext, context: "checkAndCompleteTrackIfNeeded"
        )
        let studentPresentations = allLessonPresentations.filter { $0.studentID == studentID }

        let trackLessonIDs = Set(trackLessons.map { $0.id.uuidString })
        let proficientLessonIDs = Set(studentPresentations
            .filter { $0.state == .proficient && trackLessonIDs.contains($0.lessonID) }
            .map(\.lessonID))

        guard trackLessonIDs.isSubset(of: proficientLessonIDs) else { return }

        let trackID = track.id.uuidString
        let allEnrollments = safeFetch(
            FetchDescriptor<StudentTrackEnrollment>(), modelContext: modelContext, context: "checkAndCompleteTrackIfNeeded"
        )
        if let enrollment = allEnrollments.first(where: {
            $0.studentID == studentID && $0.trackID == trackID && $0.isActive
        }) {
            enrollment.isActive = false
            if let coordinator = saveCoordinator {
                coordinator.save(modelContext, reason: "Completing track enrollment")
            } else {
                safeSave(modelContext: modelContext, context: "checkAndCompleteTrackIfNeeded")
            }
        }
    }
}
