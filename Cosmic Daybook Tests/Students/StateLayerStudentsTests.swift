import CoreData
import Foundation
import Synchronization
import Testing
@testable import CosmicDaybook

/// See `RosterStoreTests` for why these poll instead of sleeping.
@MainActor
private func waitUntil(
    timeout: Duration = .seconds(10),
    _ condition: @MainActor () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition() {
        if clock.now > deadline { return }
        try await Task.sleep(for: .milliseconds(20))
    }
}

/// Set from an observation callback, which may run on any thread.
nonisolated private final class Fired: Sendable {
    private let flag = Mutex(false)
    var value: Bool { flag.withLock { $0 } }
    func set() { flag.withLock { $0 = true } }
}

/// Which of a test's roster closures ran, in order.
@MainActor
private final class RosterReads {
    var names: [String] = []
}

/// The state layer review's B4 (2026-11-22). `@Observable` tells no one when a
/// property is set to a value equal to the old one, and an array of managed
/// objects compares by identity, so the roster rebuilt after a rename or a
/// level change (the same students in the same order) reached no view.
/// `RosterStore.refresh()` now always notifies.
@Suite("RosterStore: an edited student notifies")
@MainActor
struct RosterStoreEditNotifiesTests {

    @Test("Renaming a student tells a reader of all")
    func renameNotifiesAll() async throws {
        let dependencies = try CoreDataTestHelpers.makeDependencies()
        let roster = dependencies.roster
        let student = CoreDataTestHelpers.seedStudent(
            in: dependencies.viewContext, firstName: "Maya", lastName: "Stern"
        )
        try dependencies.viewContext.save()
        try await waitUntil { roster.all.contains(student) }

        let fired = Fired()
        _ = withObservationTracking { roster.all } onChange: { fired.set() }
        // One student, so the order can't move: `all` holds the same object
        // before and after.
        student.lastName = "Adler"
        try dependencies.viewContext.save()

        // The short names hold strings, so they show the rebuild happened.
        try await waitUntil { roster.shortNamesByFullName.values.contains("Maya A") }
        #expect(roster.shortNamesByFullName.values.contains("Maya A"), "the roster never rebuilt")
        #expect(roster.all == [student])
        #expect(fired.value, "all was rebuilt after the rename and told no one")
    }

    @Test("A level change tells a reader of enrolled, and of byID")
    func levelChangeNotifiesEnrolled() async throws {
        let dependencies = try CoreDataTestHelpers.makeDependencies()
        let roster = dependencies.roster
        let student = CoreDataTestHelpers.seedStudent(
            in: dependencies.viewContext, firstName: "Noa", lastName: "Levi", level: .lower
        )
        try dependencies.viewContext.save()
        try await waitUntil { roster.enrolled.contains(student) }

        let enrolledFired = Fired()
        let byIDFired = Fired()
        _ = withObservationTracking { roster.enrolled } onChange: { enrolledFired.set() }
        _ = withObservationTracking { roster.byID } onChange: { byIDFired.set() }
        student.level = .upper
        try dependencies.viewContext.save()
        try await waitUntil(timeout: .seconds(3)) { enrolledFired.value }
        if !enrolledFired.value {
            // Nothing a level change moves is visible from outside, so a
            // rename after it marks that the store has rebuilt since.
            student.lastName = "Katz"
            try dependencies.viewContext.save()
            try await waitUntil { roster.shortNamesByFullName.values.contains("Noa K") }
            #expect(roster.shortNamesByFullName.values.contains("Noa K"), "the roster never rebuilt")
        }

        #expect(roster.enrolled == [student])
        #expect(enrolledFired.value, "enrolled was rebuilt after the level change and told no one")
        #expect(byIDFired.value, "byID was rebuilt after the level change and told no one")
    }
}

/// The state layer review's B5 (2026-11-22). The Progress tab calls
/// `reportTitle(for:)` while it draws, and a lesson looked up for the first
/// time is remembered in `lessonsByID`. That cache was tracked, so each first
/// lookup invalidated whatever had already read it in the same pass.
@Suite("Student Progress tab: a lesson lookup while drawing notifies no one")
@MainActor
struct StudentProgressTabLookupTests {

    @Test("A first lookup of a report's lesson fires nothing")
    func cacheMissFiresNothing() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "S")
        let studentID = try #require(student.id)
        let chains = CoreDataTestHelpers.seedLesson(in: context, name: "Bead Chains", area: "Math", sequence: "Chains")
        let squares = CoreDataTestHelpers.seedLesson(
            in: context, name: "Bead Squares", area: "Math", sequence: "Chains"
        )
        // Two untitled reports, so each title comes from its lesson.
        let first = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "", studentID: studentID, lessonID: try #require(chains.id)
        )
        first.kind = .report
        let second = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "", studentID: studentID, lessonID: try #require(squares.id)
        )
        second.kind = .report
        #expect(CoreDataTestHelpers.save(context))

        let model = StudentProgressTabViewModel()
        model.configure(for: student, context: context)
        #expect(model.activeReports.count == 2)

        // A write made inside the tracked closure is never reported (the
        // observers are installed when it returns), so the first title is
        // read under tracking and the second lesson is looked up after it.
        let fired = Fired()
        let firstTitle = withObservationTracking { model.reportTitle(for: first) } onChange: { fired.set() }
        #expect(firstTitle == "Bead Chains")
        #expect(model.reportTitle(for: second) == "Bead Squares")
        #expect(!fired.value, "looking up a lesson for a title invalidated a reader")
    }
}

/// The state layer review's "debounced publishers rebuilt on every draw"
/// (2026-11-22): the roster's 300 ms wait now lives on the model, which
/// outlives a redraw, as `MeetingQueueModel.requestRefresh` does.
@Suite("Students roster: refresh requests are debounced on the model")
@MainActor
struct StudentsRefreshDebounceTests {

    @Test("Two requests inside 300 ms give one refresh, with the roster as it is then")
    func twoRequestsOneRefresh() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let model = StudentsViewModel()
        let probe = RosterReads()

        model.requestRefresh(viewContext: context, calendar: AppCalendar.shared) {
            probe.names.append("first")
            return []
        }
        model.requestRefresh(viewContext: context, calendar: AppCalendar.shared) {
            probe.names.append("second")
            return []
        }
        #expect(probe.names.isEmpty, "the refresh ran before its wait")

        try await waitUntil { !probe.names.isEmpty }
        // Long enough for a first request that wasn't cancelled to have run too.
        try await Task.sleep(for: .milliseconds(450))
        #expect(probe.names == ["second"])
        #expect(model.attendanceLoadCount == 1)
        #expect(model.tableCacheBuildCount == 1)
    }

    @Test("A model let go during its wait does no refresh")
    func releasedModelDoesNothing() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        var model: StudentsViewModel? = StudentsViewModel()
        weak let weakModel = model
        let probe = RosterReads()

        model?.requestRefresh(viewContext: context, calendar: AppCalendar.shared) {
            probe.names.append("read")
            return []
        }
        model = nil
        #expect(weakModel == nil, "the waiting task kept the model alive")
        try await Task.sleep(for: .milliseconds(450))
        #expect(probe.names.isEmpty)
    }
}
