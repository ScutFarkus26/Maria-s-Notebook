import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// The post-import pass used to sweep every entity after any import, written
// or not. The history processor already knows which entities the import
// inserted, so the pass is now scoped to them, an import event alone runs
// nothing, and only the launch pass and a failed history read sweep
// everything. Efficiency pass 2026-09-17.

@Suite("Deduplication Scope")
@MainActor
struct DeduplicationScopeTests {

    private func waitUntil(
        timeout: Duration = .seconds(30),
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    /// Two students and two lessons sharing one id each.
    private func seedDuplicates() throws -> NSManagedObjectContext {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let studentID = UUID()
        for _ in 0..<2 {
            CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "S").id = studentID
        }
        // Different names, one id: only the id-based pass should see them.
        let lessonID = UUID()
        for index in 0..<2 {
            CoreDataTestHelpers.seedLesson(in: context, name: index == 0 ? "Rectangle" : "Square").id = lessonID
        }
        CoreDataTestHelpers.save(context)
        return context
    }

    // MARK: - The scope itself

    @Test("Everything includes every entity; an insert set includes only its members")
    func scopeMembership() {
        #expect(DeduplicationScope.everything.includes("Student"))
        #expect(!DeduplicationScope.everything.isEmpty)

        let scope = DeduplicationScope(insertedEntities: ["Note", "Lesson"])
        #expect(scope.includes("Lesson"))
        #expect(!scope.includes("Student"))
        #expect(!scope.isEmpty)
        #expect(DeduplicationScope(insertedEntities: []).isEmpty)
    }

    // MARK: - The pass honours it

    @Test("A scoped pass dedups only the scoped entities and leaves the others for the full pass")
    func scopedPassSkipsOtherEntities() throws {
        let context = try seedDuplicates()

        let scoped = DataCleanupService.deduplicateAllModels(
            using: context, scope: DeduplicationScope(insertedEntities: ["Student"])
        )
        #expect(scoped == ["Student": 1])
        #expect(context.safeFetch(CDFetchRequest(CDStudent.self)).count == 1)
        #expect(context.safeFetch(CDFetchRequest(CDLesson.self)).count == 2)
        CoreDataTestHelpers.save(context)

        let full = DataCleanupService.deduplicateAllModels(using: context)
        #expect(full == ["Lesson": 1])
        #expect(context.safeFetch(CDFetchRequest(CDLesson.self)).count == 1)
    }

    @Test("The same-name lesson and same-title track merges belong to their entity's scope")
    func nameMergesFollowTheirEntity() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        CoreDataTestHelpers.seedLesson(in: context, name: "Rectangle", area: "Geometry", sequence: "Area")
        CoreDataTestHelpers.seedLesson(in: context, name: "rectangle ", area: "Geometry", sequence: "Area")
        for _ in 0..<2 {
            let track = CDTrackEntity(context: context)
            track.title = "Fractions"
        }
        CoreDataTestHelpers.save(context)

        let noteOnly = DataCleanupService.deduplicateAllModels(
            using: context, scope: DeduplicationScope(insertedEntities: ["Note"])
        )
        #expect(noteOnly.isEmpty)

        let lessonsAndTracks = DataCleanupService.deduplicateAllModels(
            using: context, scope: DeduplicationScope(insertedEntities: ["Lesson", "Track"])
        )
        #expect(lessonsAndTracks == ["Lesson (same name)": 1, "Track (same title)": 1])
    }

    @Test("Same-name lesson groups match between the narrow pre-check and the full-table pass")
    func sameNameGroupsAreEquivalent() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        CoreDataTestHelpers.seedLesson(in: context, name: "Rectangle", area: "Geometry", sequence: "Area")
        CoreDataTestHelpers.seedLesson(in: context, name: "  RECTANGLE", area: "geometry", sequence: "area ")
        CoreDataTestHelpers.seedLesson(in: context, name: "Rectangle", area: "Geometry", sequence: "Lines")
        CoreDataTestHelpers.seedLesson(in: context, name: "Triangle", area: "Geometry", sequence: "Area")
        CoreDataTestHelpers.seedLesson(in: context, name: "Triangle", area: "Geometry", sequence: "Area")
        CoreDataTestHelpers.seedLesson(in: context, name: "Triangle", area: "Geometry", sequence: "Area")
        let parsha = CoreDataTestHelpers.seedLesson(in: context, name: "Middle Girls", area: "Parsha", sequence: "")
        parsha.parshaKey = "bereishit"
        let parshaTwo = CoreDataTestHelpers.seedLesson(in: context, name: "Middle Girls", area: "Parsha", sequence: "")
        parshaTwo.parshaKey = "noach"
        CoreDataTestHelpers.save(context)

        // A clean context takes the narrow path; a dirty one falls back to the
        // full-table pass. Both must describe the same groups.
        let narrow = DataCleanupService.sameNameLessonGroups(using: context)
            .map { Set($0.compactMap(\.id)) }
        let marker = CoreDataTestHelpers.seedLesson(in: context, name: "Unsaved", area: "Geometry", sequence: "Area")
        let full = DataCleanupService.sameNameLessonGroups(using: context)
            .map { Set($0.compactMap(\.id)) }
        context.delete(marker)

        #expect(narrow.count == 2)
        #expect(narrow == full)
        #expect(narrow.map(\.count) == [2, 3])
    }

    @Test("Same-title track groups match between the narrow pre-check and the full-table pass")
    func sameTitleGroupsAreEquivalent() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        for title in ["Fractions", " fractions", "Decimals", "Decimals", "Squaring"] {
            let track = CDTrackEntity(context: context)
            track.title = title
        }
        CoreDataTestHelpers.save(context)

        let narrow = DataCleanupService.sameTitleTrackGroups(using: context).map { Set($0.compactMap(\.id)) }
        let marker = CDTrackEntity(context: context)
        marker.title = "Unsaved"
        let full = DataCleanupService.sameTitleTrackGroups(using: context).map { Set($0.compactMap(\.id)) }
        context.delete(marker)

        #expect(narrow.count == 2)
        #expect(narrow == full)
    }

    // MARK: - The coordinator resolves the scope

    @Test("A history report scopes the pass to the inserted entities")
    func historyReportScopesThePass() async {
        let coordinator = DeduplicationCoordinator(debounceInterval: .milliseconds(1))
        coordinator.requestDeduplication(insertedEntities: ["Note"])
        coordinator.requestDeduplication(insertedEntities: ["AttendanceRecord"])

        #expect(await waitUntil { coordinator.runAttemptCount == 1 })
        #expect(coordinator.lastRunScope == DeduplicationScope(insertedEntities: ["Note", "AttendanceRecord"]))
    }

    @Test("An import event with no history report runs no pass at all")
    func importEventAloneRunsNothing() async {
        let coordinator = DeduplicationCoordinator(debounceInterval: .milliseconds(1))
        coordinator.requestDeduplicationAfterImport()

        #expect(await waitUntil { coordinator.cycleCount == 1 })
        #expect(coordinator.runAttemptCount == 0)
        #expect(coordinator.lastRunScope == nil)
    }

    @Test("An import event beside a history report keeps the report's scope")
    func importEventDefersToHistoryReport() async {
        let coordinator = DeduplicationCoordinator(debounceInterval: .milliseconds(20))
        coordinator.requestDeduplicationAfterImport()
        coordinator.requestDeduplication(insertedEntities: [])

        #expect(await waitUntil { coordinator.runAttemptCount == 1 })
        #expect(coordinator.lastRunScope == DeduplicationScope(insertedEntities: []))
    }

    @Test("A plain request still sweeps everything, whatever else was reported")
    func plainRequestWidensToEverything() async {
        let coordinator = DeduplicationCoordinator(debounceInterval: .milliseconds(20))
        coordinator.requestDeduplication(insertedEntities: ["Note"])
        coordinator.requestDeduplication()

        #expect(await waitUntil { coordinator.runAttemptCount == 1 })
        #expect(coordinator.lastRunScope == .everything)
    }

    @Test("The next cycle starts from a clean scope")
    func scopeResetsBetweenCycles() async {
        let coordinator = DeduplicationCoordinator(debounceInterval: .milliseconds(1))
        coordinator.requestDeduplication()
        #expect(await waitUntil { coordinator.runAttemptCount == 1 })

        coordinator.requestDeduplication(insertedEntities: ["Note"])
        #expect(await waitUntil { coordinator.runAttemptCount == 2 })
        #expect(coordinator.lastRunScope == DeduplicationScope(insertedEntities: ["Note"]))
    }
}
