import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The Groups page's fold of the ready queue onto lessons: who is counted,
/// who only shows, and in what order the cards come.
@Suite("Ready Groups")
@MainActor
struct ReadyGroupsTests {
    private typealias Fixture = ReadyGroupsFixture

    private func build(_ snapshot: ReadyQueueSnapshot) -> ReadyGroups {
        ReadyGroups.build(from: snapshot, schoolDaysSince: { Fixture.daysSince($0) })
    }

    // MARK: - Threshold

    @Test("Two ready children make a group; one makes a single")
    func twoMakeAGroupOneASingle() throws {
        let fixture = try Fixture()
        let ada = fixture.student("Ada", "Bell")
        let ben = fixture.student("Ben", "Cole")
        let cy = fixture.student("Cy", "Dunn")
        try fixture.give([ada, ben], fixture.commutative, on: "2026-04-20", confirmed: true)
        try fixture.give([cy], fixture.triangle, on: "2026-04-28", confirmed: true)

        let built = build(try fixture.snapshot([ada, ben, cy]))

        #expect(built.groups.map(\.lessonID) == [try fixture.id(fixture.distributive)])
        #expect(built.singles.map(\.lessonID) == [try fixture.id(fixture.square)])
        #expect(built.holding.isEmpty)
        #expect(built.lessons.count == 2)
        let group = try #require(built.groups.first)
        #expect(group.ready.map(\.child.name) == ["Ada B", "Ben C"])
        #expect(group.isGroup)
        #expect(group.stepLabel == "2 of 4")
        #expect(group.area == "Math")
        #expect(group.sequence == "Laws")
        #expect(group.longestWait == 10)
        #expect(group.readyStudentUUIDs == Set([try #require(ada.id), try #require(ben.id)]))
        #expect(built.areaCounts == [
            ReadyGroups.AreaCount(area: "Geometry", groups: 0, singles: 1),
            ReadyGroups.AreaCount(area: "Math", groups: 1, singles: 0)
        ])
    }

    @Test("An area filter keeps the area chips whole")
    func areaFilterKeepsCounts() throws {
        let fixture = try Fixture()
        let ada = fixture.student("Ada", "Bell")
        let ben = fixture.student("Ben", "Cole")
        let cy = fixture.student("Cy", "Dunn")
        try fixture.give([ada, ben], fixture.commutative, on: "2026-04-20", confirmed: true)
        try fixture.give([cy], fixture.triangle, on: "2026-04-28", confirmed: true)
        let built = build(try fixture.snapshot([ada, ben, cy]))

        let geometry = built.inArea("geometry")

        #expect(geometry.lessons.map(\.lessonID) == [try fixture.id(fixture.square)])
        #expect(geometry.groups.isEmpty)
        #expect(geometry.singles.count == 1)
        #expect(geometry.areaCounts == built.areaCounts)
        #expect(built.inArea(nil) == built)
    }

    // MARK: - Planned

    @Test("A child on a plan for the lesson is not ready; the plan shows who and when")
    func plannedChildIsNotReady() throws {
        let fixture = try Fixture()
        let ada = fixture.student("Ada", "Bell")
        let ben = fixture.student("Ben", "Cole")
        let cy = fixture.student("Cy", "Dunn")
        let dee = fixture.student("Dee", "Eng")
        try fixture.give([ada, ben, cy, dee], fixture.commutative, on: "2026-04-20", confirmed: true)
        let draft = try fixture.plan([cy], fixture.distributive, on: "2026-05-04")
        try fixture.yearPlan(dee, fixture.distributive, on: "2026-05-11")

        let built = build(try fixture.snapshot([ada, ben, cy, dee]))
        let group = try #require(built.group(for: try fixture.id(fixture.distributive)))

        #expect(group.ready.map(\.child.name) == ["Ada B", "Ben C"])
        #expect(group.almost.isEmpty)
        #expect(group.plannedWith.count == 2)
        let presentation = try #require(group.plannedWith.first)
        #expect(presentation.assignmentID == draft.objectID)
        #expect(presentation.date == (try CoreDataTestHelpers.day("2026-05-04")))
        #expect(presentation.children.map(\.name) == ["Cy D"])
        #expect(presentation.isYearPlan == false)
        let yearPlan = try #require(group.plannedWith.last)
        #expect(yearPlan.isYearPlan)
        #expect(yearPlan.date == AppCalendar.startOfDay(try CoreDataTestHelpers.day("2026-05-11")))
        #expect(yearPlan.children.map(\.name) == ["Dee E"])
    }

    // MARK: - Catch-up

    @Test("A child ready for N shows on next(N)'s card only when that card exists, uncounted")
    func catchUpOnlyWhenTheCardExists() throws {
        let fixture = try Fixture()
        let ada = fixture.student("Ada", "Bell")
        let ben = fixture.student("Ben", "Cole")
        let cy = fixture.student("Cy", "Dunn")
        let eve = fixture.student("Eve", "Ford")
        // Ada and Ben are ready for Associative (step 3): that card exists.
        try fixture.give([ada, ben], fixture.distributive, on: "2026-04-22", confirmed: true)
        // Cy is ready for Distributive (step 2), so she could join Associative.
        try fixture.give([cy], fixture.commutative, on: "2026-04-16", confirmed: true)
        // Eve is ready for Square; nobody is ready for Pentagon, so no ghost.
        try fixture.give([eve], fixture.triangle, on: "2026-04-16", confirmed: true)

        let built = build(try fixture.snapshot([ada, ben, cy, eve]))
        let associative = try #require(built.group(for: try fixture.id(fixture.associative)))

        #expect(associative.ready.map(\.child.name) == ["Ada B", "Ben C"])
        #expect(associative.catchUp.map(\.child.name) == ["Cy D"])
        let ghost = try #require(associative.catchUp.first)
        #expect(ghost.afterLessonID == (try fixture.id(fixture.distributive)))
        #expect(ghost.afterLessonName == "Distributive Law")
        #expect(ghost.waitSchoolDays == 14)
        #expect(associative.longestWait == 8)
        #expect(built.group(for: try fixture.id(fixture.pentagon)) == nil)
        #expect(built.group(for: try fixture.id(fixture.square))?.catchUp.isEmpty == true)
        #expect(built.group(for: try fixture.id(fixture.distributive))?.ready.map(\.child.name) == ["Cy D"])
    }

    // MARK: - Unconfirmed

    @Test("Unconfirmed children show only on group cards and are never counted")
    func unconfirmedOnlyOnGroupCards() throws {
        let fixture = try Fixture()
        let ada = fixture.student("Ada", "Bell")
        let ben = fixture.student("Ben", "Cole")
        let cy = fixture.student("Cy", "Dunn")
        let dee = fixture.student("Dee", "Eng")
        let eve = fixture.student("Eve", "Ford")
        try fixture.give([ada, ben], fixture.commutative, on: "2026-04-20", confirmed: true)
        let cyGiven = try fixture.give([cy], fixture.commutative, on: "2026-04-21")
        try fixture.give([eve], fixture.triangle, on: "2026-04-20", confirmed: true)
        try fixture.give([dee], fixture.triangle, on: "2026-04-21")

        let built = build(try fixture.snapshot([ada, ben, cy, dee, eve]))
        let group = try #require(built.group(for: try fixture.id(fixture.distributive)))
        let single = try #require(built.group(for: try fixture.id(fixture.square)))

        #expect(group.ready.count == 2)
        #expect(group.unconfirmed.map(\.child.name) == ["Cy D"])
        let line = try #require(group.unconfirmed.first)
        #expect(line.assignmentID == cyGiven.objectID)
        #expect(line.previousLessonID == (try fixture.id(fixture.commutative)))
        #expect(line.lastGiven == AppCalendar.startOfDay(try CoreDataTestHelpers.day("2026-04-21")))
        #expect(single.ready.map(\.child.name) == ["Eve F"])
        #expect(single.unconfirmed.isEmpty)
        #expect(built.singles.map(\.lessonID) == [single.lessonID])
    }

    // MARK: - Order

    @Test("Cards sort by ready count, then longest wait, then lesson name")
    func sortOrder() throws {
        let fixture = try Fixture()
        let kids = (0..<9).map { fixture.student("Kid\($0)", "Test") }
        // Distributive: 2 ready, waiting 10. Associative: 3 ready, waiting 2.
        try fixture.give([kids[0], kids[1]], fixture.commutative, on: "2026-04-20", confirmed: true)
        try fixture.give([kids[2], kids[3], kids[4]], fixture.distributive, on: "2026-04-28", confirmed: true)
        // Square: 2 ready, waiting 30. Pentagon and Identity: 1 ready each, waiting 1.
        try fixture.give([kids[5], kids[6]], fixture.triangle, on: "2026-03-31", confirmed: true)
        try fixture.give([kids[7]], fixture.square, on: "2026-04-29", confirmed: true)
        try fixture.give([kids[8]], fixture.associative, on: "2026-04-29", confirmed: true)

        let built = build(try fixture.snapshot(kids))

        let expected = try [
            fixture.associative, fixture.square, fixture.distributive, fixture.identity, fixture.pentagon
        ].map { try fixture.id($0) }
        #expect(built.lessons.map(\.lessonID) == expected)
        #expect(built.lessons.map(\.longestWait) == [2, 30, 10, 1, 1])
        #expect(built.groups.map(\.lessonID) == Array(expected.prefix(3)))
        #expect(built.singles.map(\.lessonID) == Array(expected.suffix(2)))
    }

    // MARK: - Levels

    @Test("The level filter is applied before the 2+ threshold counts")
    func levelFilter() throws {
        let fixture = try Fixture()
        let ada = fixture.student("Ada", "Bell", level: .lower)
        let ben = fixture.student("Ben", "Cole", level: .lower)
        let cy = fixture.student("Cy", "Dunn", level: .upper)
        let dee = fixture.student("Dee", "Eng", level: .upper)
        try fixture.give([ada, ben, cy], fixture.commutative, on: "2026-04-20", confirmed: true)
        try fixture.plan([dee], fixture.distributive, on: "2026-05-04")
        let snapshot = try fixture.snapshot([ada, ben, cy, dee])
        let distributive = try fixture.id(fixture.distributive)

        #expect(snapshot.roster.levels == [.lower, .upper])
        #expect(build(snapshot).group(for: distributive)?.ready.count == 3)
        #expect(build(snapshot).group(for: distributive)?.plannedWith.count == 1)

        let lower = build(snapshot.filtered(levels: [.lower]))
        #expect(lower.groups.map(\.lessonID) == [distributive])
        #expect(lower.group(for: distributive)?.ready.map(\.child.name) == ["Ada B", "Ben C"])
        #expect(lower.group(for: distributive)?.plannedWith.isEmpty == true)

        let upper = build(snapshot.filtered(levels: [.upper]))
        #expect(upper.groups.isEmpty)
        #expect(upper.singles.map(\.lessonID) == [distributive])
        #expect(upper.group(for: distributive)?.plannedWith.first?.children.map(\.name) == ["Dee E"])

        #expect(build(snapshot.filtered(levels: nil)) == build(snapshot))
    }

    // MARK: - Practice gate

    @Test("A child is Almost here exactly when the ready queue says so")
    func practiceGateMatchesTheEngine() throws {
        let fixture = try Fixture()
        fixture.requirePractice(area: "Math", sequence: "Laws")
        let ada = fixture.student("Ada", "Bell")
        let ben = fixture.student("Ben", "Cole")
        let cy = fixture.student("Cy", "Dunn")
        let dee = fixture.student("Dee", "Eng")
        let students = [ada, ben, cy, dee]
        try fixture.give(students, fixture.commutative, on: "2026-04-20", confirmed: true)
        try fixture.work(cy, on: fixture.commutative, status: "active")
        try fixture.work(dee, on: fixture.commutative, status: "complete")
        // Ada and Ben have no work at all: not held (the queue's rule).

        let snapshot = try fixture.snapshot(students)
        let built = build(snapshot)
        let group = try #require(built.group(for: try fixture.id(fixture.distributive)))

        #expect(group.ready.map(\.child.name) == ["Ada B", "Ben C", "Dee E"])
        #expect(group.almost.map(\.child.name) == ["Cy D"])
        #expect(group.almost.first?.reason == "practice on Commutative Law not yet complete")
        #expect(group.ready.allSatisfy { $0.reason == nil })

        let engineAlmost = Set(snapshot.items.filter { $0.tier == .almostReady }.map(\.studentID))
        let engineReady = Set(snapshot.items.filter { $0.tier == .ready }.map(\.studentID))
        #expect(engineAlmost == [try fixture.id(cy)])
        #expect(Set(built.lessons.flatMap(\.almost).map(\.child.id)) == engineAlmost)
        #expect(Set(built.lessons.flatMap(\.ready).map(\.child.id)) == engineReady)
    }

    @Test("A lesson only gate-held children wait on is holding, not a group or a single")
    func almostOnlyIsHolding() throws {
        let fixture = try Fixture()
        fixture.requirePractice(area: "Geometry", sequence: "Shapes")
        let ada = fixture.student("Ada", "Bell")
        try fixture.give([ada], fixture.triangle, on: "2026-04-20", confirmed: true)
        try fixture.work(ada, on: fixture.triangle, status: "active")

        let built = build(try fixture.snapshot([ada]))

        #expect(built.groups.isEmpty)
        #expect(built.singles.isEmpty)
        #expect(built.holding.map(\.lessonID) == [try fixture.id(fixture.square)])
        #expect(built.holding.first?.longestWait == nil)
        #expect(built.areaCounts.isEmpty)
    }
}
