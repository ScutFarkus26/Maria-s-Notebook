import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The controller reports a change on the next run-loop turn after a save, and
/// a main-actor task can wait a while for a turn under suite contention — so
/// assertions poll for the expected state instead of sleeping a fixed interval.
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

/// `RosterStore` replaces the whole-table `@FetchRequest` every student view
/// used to hold. These pin what a view relies on: a save shows up in `all`,
/// `enrolled` and `byID` with no manual refresh, withdrawal moves a student
/// out of `enrolled` only, the order is the roster screen's, and each
/// `AppDependencies` graph gets its own store on its own context.
@Suite("RosterStore: one live roster per workspace")
@MainActor
struct RosterStoreTests {

    @Test("A saved student appears in all, enrolled and byID without a manual refresh")
    func savedStudentAppearsEverywhere() async throws {
        let dependencies = try CoreDataTestHelpers.makeDependencies()
        let roster = dependencies.roster
        #expect(roster.all.isEmpty)

        let student = CoreDataTestHelpers.seedStudent(
            in: dependencies.viewContext, firstName: "Maya", lastName: "Stern"
        )
        try dependencies.viewContext.save()
        let id = try #require(student.id)

        try await waitUntil { roster.byID[id] != nil }
        #expect(roster.all.contains(student))
        #expect(roster.enrolled.contains(student))
        #expect(roster.student(id: id) === student)
    }

    @Test("A withdrawn student leaves enrolled but stays in all")
    func withdrawnStudentLeavesEnrolledOnly() async throws {
        let dependencies = try CoreDataTestHelpers.makeDependencies()
        let roster = dependencies.roster
        let student = CoreDataTestHelpers.seedStudent(in: dependencies.viewContext, firstName: "Noa", lastName: "Levi")
        try dependencies.viewContext.save()
        try await waitUntil { roster.enrolled.contains(student) }

        student.enrollmentStatus = .withdrawn
        try dependencies.viewContext.save()

        try await waitUntil { !roster.enrolled.contains(student) }
        #expect(!roster.enrolled.contains(student))
        #expect(roster.all.contains(student))
        #expect(roster.student(id: try #require(student.id)) === student)
    }

    @Test("all is in the roster screen's order: first name, then last name")
    func allIsInFirstNameOrder() async throws {
        let dependencies = try CoreDataTestHelpers.makeDependencies()
        let roster = dependencies.roster
        CoreDataTestHelpers.seedStudent(in: dependencies.viewContext, firstName: "Zev", lastName: "Adler")
        CoreDataTestHelpers.seedStudent(in: dependencies.viewContext, firstName: "Ari", lastName: "Katz")
        CoreDataTestHelpers.seedStudent(in: dependencies.viewContext, firstName: "Ari", lastName: "Baum")
        try dependencies.viewContext.save()

        try await waitUntil { roster.all.count == 3 }
        #expect(roster.all.map(\.shortName) == ["Ari B", "Ari K", "Zev A"])
    }

    @Test("A deleted student leaves the roster")
    func deletedStudentLeaves() async throws {
        let dependencies = try CoreDataTestHelpers.makeDependencies()
        let roster = dependencies.roster
        let student = CoreDataTestHelpers.seedStudent(in: dependencies.viewContext)
        try dependencies.viewContext.save()
        let id = try #require(student.id)
        try await waitUntil { roster.student(id: id) != nil }

        dependencies.viewContext.delete(student)
        try dependencies.viewContext.save()

        try await waitUntil { roster.student(id: id) == nil }
        #expect(roster.all.isEmpty)
        #expect(roster.byID[id] == nil)
    }

    @Test("Each AppDependencies graph gets its own stores, bound to its own context")
    func storesFollowTheirGraph() async throws {
        let first = try CoreDataTestHelpers.makeDependencies()
        let second = try CoreDataTestHelpers.makeDependencies()

        #expect(first.roster === first.roster)
        #expect(first.roster !== second.roster)
        #expect(first.roster.context === first.viewContext)
        #expect(second.roster.context === second.viewContext)
        #expect(first.lessonCatalog !== second.lessonCatalog)
        #expect(first.lessonCatalog.context === first.viewContext)
        #expect(second.lessonCatalog.context === second.viewContext)

        // A save in one graph never reaches the other's roster.
        let student = CoreDataTestHelpers.seedStudent(in: second.viewContext, firstName: "Only", lastName: "Second")
        try second.viewContext.save()
        try await waitUntil { second.roster.all.contains(student) }
        #expect(first.roster.all.isEmpty)
    }
}
