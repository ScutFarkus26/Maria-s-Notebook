#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Track Creation Tests

@Suite("GroupTrackService Track Creation Tests", .serialized)
@MainActor
struct GroupTrackServiceTrackCreationTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            GroupTrack.self,
            Track.self,
            TrackStep.self,
            Lesson.self,
            StudentTrackEnrollment.self,
        ])
    }

    @Test("getOrCreateGroupTrack creates new track when none exists")
    func createsNewTrackWhenNoneExists() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let track = try GroupTrackService.getOrCreateGroupTrack(
            subject: "Math",
            group: "Decimal System",
            modelContext: context
        )

        #expect(track.subject == "Math")
        #expect(track.group == "Decimal System")
        #expect(track.isSequential == true)
        #expect(track.isExplicitlyDisabled == false)
    }

    @Test("getOrCreateGroupTrack returns existing track")
    func returnsExistingTrack() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Create initial track
        let existing = GroupTrack(subject: "Math", group: "Addition", isSequential: false)
        context.insert(existing)

        // Should return the existing one
        let fetched = try GroupTrackService.getOrCreateGroupTrack(
            subject: "Math",
            group: "Addition",
            modelContext: context
        )

        #expect(fetched.id == existing.id)
        #expect(fetched.isSequential == false)
    }

    @Test("getOrCreateGroupTrack matching is case insensitive")
    func matchingIsCaseInsensitive() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Create with lowercase
        let existing = GroupTrack(subject: "math", group: "addition")
        context.insert(existing)

        // Query with different case
        let fetched = try GroupTrackService.getOrCreateGroupTrack(
            subject: "MATH",
            group: "ADDITION",
            modelContext: context
        )

        #expect(fetched.id == existing.id)
    }

    @Test("getOrCreateGroupTrack trims whitespace")
    func trimsWhitespace() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Create with trimmed values
        let existing = GroupTrack(subject: "Math", group: "Addition")
        context.insert(existing)

        // Query with whitespace
        let fetched = try GroupTrackService.getOrCreateGroupTrack(
            subject: "  Math  ",
            group: "  Addition  ",
            modelContext: context
        )

        #expect(fetched.id == existing.id)
    }
}

// MARK: - Track Lookup Tests

@Suite("GroupTrackService Track Lookup Tests", .serialized)
@MainActor
struct GroupTrackServiceTrackLookupTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            GroupTrack.self,
            Track.self,
            TrackStep.self,
            Lesson.self,
            StudentTrackEnrollment.self,
        ])
    }

    @Test("getGroupTrack returns nil when no track exists")
    func returnsNilWhenNoTrackExists() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let track = try GroupTrackService.getGroupTrack(
            subject: "Math",
            group: "Nonexistent",
            modelContext: context
        )

        #expect(track == nil)
    }

    @Test("getGroupTrack returns existing track")
    func returnsExistingTrack() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let existing = GroupTrack(subject: "Math", group: "Addition")
        context.insert(existing)

        let track = try GroupTrackService.getGroupTrack(
            subject: "Math",
            group: "Addition",
            modelContext: context
        )

        #expect(track?.id == existing.id)
    }

    @Test("getEffectiveTrackSettings returns default for non-existent track")
    func returnsDefaultSettingsForNonExistent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let settings = try GroupTrackService.getEffectiveTrackSettings(
            subject: "Math",
            group: "Nonexistent",
            modelContext: context
        )

        #expect(settings.isSequential == true)
        #expect(settings.isExplicitlyDisabled == false)
    }

    @Test("getEffectiveTrackSettings returns actual settings for existing track")
    func returnsActualSettingsForExisting() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let existing = GroupTrack(subject: "Math", group: "Addition", isSequential: false)
        context.insert(existing)

        let settings = try GroupTrackService.getEffectiveTrackSettings(
            subject: "Math",
            group: "Addition",
            modelContext: context
        )

        #expect(settings.isSequential == false)
        #expect(settings.isExplicitlyDisabled == false)
    }
}

// MARK: - isTrack Tests

@Suite("GroupTrackService isTrack Tests", .serialized)
@MainActor
struct GroupTrackServiceIsTrackTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            GroupTrack.self,
            Track.self,
            TrackStep.self,
            Lesson.self,
            StudentTrackEnrollment.self,
        ])
    }

    @Test("isTrack returns true by default when no record exists")
    func returnsTrueByDefault() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let result = GroupTrackService.isTrack(
            subject: "Math",
            group: "NewGroup",
            modelContext: context
        )

        #expect(result == true)
    }

    @Test("isTrack returns true when track exists and not disabled")
    func returnsTrueWhenNotDisabled() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let track = GroupTrack(subject: "Math", group: "Addition", isExplicitlyDisabled: false)
        context.insert(track)

        let result = GroupTrackService.isTrack(
            subject: "Math",
            group: "Addition",
            modelContext: context
        )

        #expect(result == true)
    }

    @Test("isTrack returns false when explicitly disabled")
    func returnsFalseWhenDisabled() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let track = GroupTrack(subject: "Math", group: "Addition", isExplicitlyDisabled: true)
        context.insert(track)

        let result = GroupTrackService.isTrack(
            subject: "Math",
            group: "Addition",
            modelContext: context
        )

        #expect(result == false)
    }
}

// MARK: - removeTrack Tests

@Suite("GroupTrackService removeTrack Tests", .serialized)
@MainActor
struct GroupTrackServiceRemoveTrackTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            GroupTrack.self,
            Track.self,
            TrackStep.self,
            Lesson.self,
            StudentTrackEnrollment.self,
        ])
    }

    @Test("removeTrack marks existing track as disabled")
    func marksExistingAsDisabled() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let track = GroupTrack(subject: "Math", group: "Addition", isExplicitlyDisabled: false)
        context.insert(track)

        try GroupTrackService.removeTrack(
            subject: "Math",
            group: "Addition",
            modelContext: context
        )

        #expect(track.isExplicitlyDisabled == true)
    }

    @Test("removeTrack creates disabled record when none exists")
    func createsDisabledRecordWhenNoneExists() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        try GroupTrackService.removeTrack(
            subject: "Math",
            group: "NewGroup",
            modelContext: context
        )

        let track = try GroupTrackService.getGroupTrack(
            subject: "Math",
            group: "NewGroup",
            modelContext: context
        )

        #expect(track != nil)
        #expect(track?.isExplicitlyDisabled == true)
    }
}

// MARK: - getAllGroupTracks Tests

@Suite("GroupTrackService getAllGroupTracks Tests", .serialized)
@MainActor
struct GroupTrackServiceGetAllGroupTracksTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            GroupTrack.self,
            Track.self,
            TrackStep.self,
            Lesson.self,
            StudentTrackEnrollment.self,
        ])
    }

    @Test("getAllGroupTracks returns all existing tracks")
    func returnsAllExistingTracks() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let track1 = GroupTrack(subject: "Math", group: "Addition")
        let track2 = GroupTrack(subject: "Language", group: "Reading")
        let track3 = GroupTrack(subject: "Math", group: "Subtraction")
        context.insert(track1)
        context.insert(track2)
        context.insert(track3)

        let tracks = try GroupTrackService.getAllGroupTracks(modelContext: context)

        #expect(tracks.count == 3)
    }

    @Test("getAllGroupTracks returns sorted by subject then group")
    func returnsSortedTracks() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let track1 = GroupTrack(subject: "Zoology", group: "Animals")
        let track2 = GroupTrack(subject: "Math", group: "Addition")
        let track3 = GroupTrack(subject: "Math", group: "Subtraction")
        context.insert(track1)
        context.insert(track2)
        context.insert(track3)

        let tracks = try GroupTrackService.getAllGroupTracks(modelContext: context)

        #expect(tracks[0].subject == "Math")
        #expect(tracks[0].group == "Addition")
        #expect(tracks[1].subject == "Math")
        #expect(tracks[1].group == "Subtraction")
        #expect(tracks[2].subject == "Zoology")
    }

    @Test("getAllGroupTracks returns empty for empty database")
    func returnsEmptyForEmptyDatabase() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let tracks = try GroupTrackService.getAllGroupTracks(modelContext: context)

        #expect(tracks.isEmpty)
    }
}

// MARK: - getLessonsForTrack Tests

@Suite("GroupTrackService getLessonsForTrack Tests", .serialized)
@MainActor
struct GroupTrackServiceGetLessonsForTrackTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            GroupTrack.self,
            Track.self,
            TrackStep.self,
            Lesson.self,
            StudentTrackEnrollment.self,
        ])
    }

    @Test("getLessonsForTrack returns matching lessons")
    func returnsMatchingLessons() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let track = GroupTrack(subject: "Math", group: "Operations")
        context.insert(track)

        let lesson1 = makeTestLesson(name: "Addition", subject: "Math", group: "Operations", orderInGroup: 1)
        let lesson2 = makeTestLesson(name: "Subtraction", subject: "Math", group: "Operations", orderInGroup: 2)
        let lesson3 = makeTestLesson(name: "Reading", subject: "Language", group: "Reading", orderInGroup: 1)
        context.insert(lesson1)
        context.insert(lesson2)
        context.insert(lesson3)

        let allLessons = [lesson1, lesson2, lesson3]
        let trackLessons = GroupTrackService.getLessonsForTrack(track: track, allLessons: allLessons)

        #expect(trackLessons.count == 2)
        #expect(trackLessons.allSatisfy { $0.subject == "Math" && $0.group == "Operations" })
    }

    @Test("getLessonsForTrack sorts by orderInGroup for sequential tracks")
    func sortsByOrderForSequentialTracks() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let track = GroupTrack(subject: "Math", group: "Operations", isSequential: true)
        context.insert(track)

        let lesson1 = makeTestLesson(name: "Third", subject: "Math", group: "Operations", orderInGroup: 3)
        let lesson2 = makeTestLesson(name: "First", subject: "Math", group: "Operations", orderInGroup: 1)
        let lesson3 = makeTestLesson(name: "Second", subject: "Math", group: "Operations", orderInGroup: 2)

        let allLessons = [lesson1, lesson2, lesson3]
        let trackLessons = GroupTrackService.getLessonsForTrack(track: track, allLessons: allLessons)

        #expect(trackLessons[0].name == "First")
        #expect(trackLessons[1].name == "Second")
        #expect(trackLessons[2].name == "Third")
    }

    @Test("getLessonsForTrack uses name as fallback when order equal")
    func usesNameAsFallback() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let track = GroupTrack(subject: "Math", group: "Operations", isSequential: true)
        context.insert(track)

        let lesson1 = makeTestLesson(name: "Zebra", subject: "Math", group: "Operations", orderInGroup: 1)
        let lesson2 = makeTestLesson(name: "Apple", subject: "Math", group: "Operations", orderInGroup: 1)

        let allLessons = [lesson1, lesson2]
        let trackLessons = GroupTrackService.getLessonsForTrack(track: track, allLessons: allLessons)

        #expect(trackLessons[0].name == "Apple")
        #expect(trackLessons[1].name == "Zebra")
    }

    @Test("getLessonsForTrack returns empty when no matches")
    func returnsEmptyWhenNoMatches() {
        let track = GroupTrack(subject: "Math", group: "Operations")

        let lesson = makeTestLesson(name: "Reading", subject: "Language", group: "Reading")

        let trackLessons = GroupTrackService.getLessonsForTrack(track: track, allLessons: [lesson])

        #expect(trackLessons.isEmpty)
    }
}

// MARK: - GroupTrack Model Tests

@Suite("GroupTrack Model Tests", .serialized)
struct GroupTrackModelTests {

    @Test("GroupTrack initializes with required fields")
    func initializesWithRequiredFields() {
        let track = GroupTrack(subject: "Math", group: "Addition")

        #expect(track.subject == "Math")
        #expect(track.group == "Addition")
        #expect(track.isSequential == true)
        #expect(track.isExplicitlyDisabled == false)
    }

    @Test("GroupTrack groupKey computed correctly")
    func groupKeyComputedCorrectly() {
        let track = GroupTrack(subject: "Math", group: "Addition")

        #expect(track.groupKey == "Math|Addition")
    }

    @Test("GroupTrack trims input on initialization")
    func trimsInputOnInit() {
        let track = GroupTrack(subject: "  Math  ", group: "  Addition  ")

        #expect(track.subject == "Math")
        #expect(track.group == "Addition")
    }
}

#endif
