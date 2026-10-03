import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// One sub-area as a ladder: every child once, on the step she is up to,
/// with the tier the ready queue and the record give her.
@Suite("Sequence Ladder")
@MainActor
struct SequenceLadderTests {
    private typealias Fixture = ReadyGroupsFixture

    private func ladder(
        _ snapshot: ReadyQueueSnapshot, area: String = "Math", sequence: String = "Laws"
    ) throws -> SequenceLadder {
        try #require(SequenceLadder.build(
            area: area, sequence: sequence, from: snapshot, schoolDaysSince: { Fixture.daysSince($0) }
        ))
    }

    /// The rung a child stands on, and the step it is.
    private func rung(_ name: String, in ladder: SequenceLadder) -> (step: Int, rung: SequenceLadder.Rung)? {
        for step in ladder.steps {
            if let rung = step.children.first(where: { $0.child.name == name }) {
                return (step.position.step, rung)
            }
        }
        return nil
    }

    // MARK: - Frontiers

    /// Seven children, one for each place on the ladder. Returns them and
    /// Cy's unconfirmed Distributive assignment.
    private func seedEveryPlace(
        in fixture: Fixture
    ) throws -> (students: [CDStudent], cyDistributive: CDLessonAssignment) {
        fixture.requirePractice(area: "Math", sequence: "Laws")
        let names = [("Ada", "Bell"), ("Ben", "Cole"), ("Cy", "Dunn"), ("Dee", "Eng"),
                     ("Eve", "Ford"), ("Fay", "Gold"), ("Gil", "Hart")]
        let students = names.map { fixture.student($0.0, $0.1) }
        let (ada, ben, cy, dee) = (students[0], students[1], students[2], students[3])
        let (eve, gil) = (students[4], students[6])

        try fixture.give([ada, ben, dee], fixture.commutative, on: "2026-04-20", confirmed: true)
        try fixture.work(ben, on: fixture.commutative, status: "active")
        try fixture.plan([dee], fixture.distributive, on: "2026-05-04")
        try fixture.give([cy], fixture.commutative, on: "2026-04-01", confirmed: true)
        let cyDistributive = try fixture.give([cy], fixture.distributive, on: "2026-04-15")
        for lesson in fixture.laws {
            try fixture.give([eve], lesson, on: "2026-03-02", confirmed: true)
        }
        try fixture.yearPlan(gil, fixture.commutative, on: "2026-05-11")
        return (students, cyDistributive)
    }

    @Test("Each child stands once: on the step after the highest she was given, finished, or not started")
    func everyChildStandsOnce() throws {
        let fixture = try Fixture()
        let (students, _) = try seedEveryPlace(in: fixture)
        let built = try ladder(try fixture.snapshot(students))

        #expect(built.area == "Math")
        #expect(built.sequence == "Laws")
        let stepNames: [String] = built.steps.map(\.position.name)
        #expect(stepNames == ["Commutative Law", "Distributive Law", "Associative Law", "Identity"])
        let names: [[String]] = built.steps.map { step in step.children.map(\.child.name) }
        #expect(names == [["Gil H"], ["Ada B", "Ben C", "Dee E"], ["Cy D"], []])
        #expect(built.finished.map(\.name) == ["Eve F"])
        #expect(built.notStarted.map(\.name) == ["Fay G"])

        let onRungs: [String] = built.steps.flatMap(\.children).map(\.child.id)
        let offRungs: [String] = (built.finished + built.notStarted).map(\.id)
        let roster: [String] = try students.map { try fixture.id($0) }
        #expect(onRungs.count + offRungs.count == roster.count)
        #expect(Set(onRungs + offRungs) == Set(roster))
    }

    @Test("A child's tier comes from her plan, then the ready queue, then the record")
    func tiersOnTheFrontier() throws {
        let fixture = try Fixture()
        let (students, cyDistributive) = try seedEveryPlace(in: fixture)
        let built = try ladder(try fixture.snapshot(students))

        let ada = try #require(rung("Ada B", in: built))
        #expect(ada.step == 2)
        #expect(ada.rung.tier == .ready)
        #expect(ada.rung.lastStepGiven == 1)
        #expect(ada.rung.waitSchoolDays == 10)

        let ben = try #require(rung("Ben C", in: built)).rung
        #expect(ben.tier == .practiceOpen)
        #expect(ben.reason == "practice on Commutative Law not yet complete")

        let dee = try #require(rung("Dee E", in: built)).rung
        #expect(dee.tier == .planned)
        #expect(dee.plannedDate == (try CoreDataTestHelpers.day("2026-05-04")))

        let cy = try #require(rung("Cy D", in: built))
        #expect(cy.step == 3)
        #expect(cy.rung.tier == .unconfirmed)
        #expect(cy.rung.lastStepGiven == 2)
        #expect(cy.rung.confirmAssignmentID == cyDistributive.objectID)

        let gil = try #require(rung("Gil H", in: built))
        let gilPlanned: Date = AppCalendar.startOfDay(try CoreDataTestHelpers.day("2026-05-11"))
        #expect(gil.step == 1)
        #expect(gil.rung.tier == .planned)
        #expect(gil.rung.lastStepGiven == nil)
        #expect(gil.rung.plannedDate == gilPlanned)
    }

    @Test("Practice-open on the ladder is exactly the queue's almost ready")
    func practiceOpenMatchesTheEngine() throws {
        let fixture = try Fixture()
        fixture.requirePractice(area: "Math", sequence: "Laws")
        let ada = fixture.student("Ada", "Bell")
        let ben = fixture.student("Ben", "Cole")
        let cy = fixture.student("Cy", "Dunn")
        try fixture.give([ada, ben, cy], fixture.commutative, on: "2026-04-20", confirmed: true)
        try fixture.work(ben, on: fixture.commutative, status: "active")
        try fixture.work(cy, on: fixture.commutative, status: "complete")

        let snapshot = try fixture.snapshot([ada, ben, cy])
        let built = try ladder(snapshot)
        let rungs = built.steps.flatMap(\.children)

        let engineAlmost = Set(snapshot.items.filter { $0.tier == .almostReady }.map(\.studentID))
        #expect(engineAlmost == [try fixture.id(ben)])
        #expect(Set(rungs.filter { $0.tier == .practiceOpen }.map(\.child.id)) == engineAlmost)
        #expect(rungs.filter { $0.tier == .ready }.map(\.child.name) == ["Ada B", "Cy D"])
    }

    // MARK: - Catch-up

    @Test("Catch-up ghosts are the Groups page's own")
    func catchUpFollowsReadyGroups() throws {
        let fixture = try Fixture()
        let ada = fixture.student("Ada", "Bell")
        let ben = fixture.student("Ben", "Cole")
        let cy = fixture.student("Cy", "Dunn")
        try fixture.give([ada, ben], fixture.distributive, on: "2026-04-22", confirmed: true)
        try fixture.give([cy], fixture.commutative, on: "2026-04-16", confirmed: true)

        let snapshot = try fixture.snapshot([ada, ben, cy])
        let built = try ladder(snapshot)
        let groups = ReadyGroups.build(from: snapshot, schoolDaysSince: { Fixture.daysSince($0) })
        let associative = try fixture.id(fixture.associative)

        #expect(built.steps[2].catchUp.map(\.child.name) == ["Cy D"])
        #expect(built.steps[2].catchUp == groups.group(for: associative)?.catchUp)
        #expect(built.steps[3].catchUp.isEmpty)
        #expect(built.steps[1].children.map(\.child.name) == ["Cy D"])
    }

    // MARK: - Finding the sub-area

    @Test("The sub-area matches trimmed and case-insensitive; an unknown one has no ladder")
    func findsTheSubArea() throws {
        let fixture = try Fixture()
        let ada = fixture.student("Ada", "Bell")
        let snapshot = try fixture.snapshot([ada])

        let built = try ladder(snapshot, area: " math ", sequence: "LAWS")
        #expect(built.steps.count == 4)
        #expect(built.notStarted.map(\.name) == ["Ada B"])
        #expect(SequenceLadder.build(
            area: "Math", sequence: "Fractions", from: snapshot, schoolDaysSince: { Fixture.daysSince($0) }
        ) == nil)
        #expect(snapshot.order.areas == ["Geometry", "Math"])
        #expect(snapshot.order.sequences(inArea: "math") == ["Laws"])
        let square = try #require(snapshot.order.position(of: try fixture.id(fixture.square)))
        #expect(square.stepLabel == "2 of 3")
        #expect(square.previousLessonID == (try fixture.id(fixture.triangle)))
        #expect(square.nextLessonID == (try fixture.id(fixture.pentagon)))
    }

    @Test("The level filter narrows every list")
    func levelFilter() throws {
        let fixture = try Fixture()
        let ada = fixture.student("Ada", "Bell", level: .lower)
        let ben = fixture.student("Ben", "Cole", level: .upper)
        let cy = fixture.student("Cy", "Dunn", level: .upper)
        try fixture.give([ada, ben], fixture.commutative, on: "2026-04-20", confirmed: true)
        let snapshot = try fixture.snapshot([ada, ben, cy])

        let upper = try ladder(snapshot.filtered(levels: [.upper]))
        #expect(upper.steps[1].children.map(\.child.name) == ["Ben C"])
        #expect(upper.notStarted.map(\.name) == ["Cy D"])

        let lower = try ladder(snapshot.filtered(levels: [.lower]))
        #expect(lower.steps[1].children.map(\.child.name) == ["Ada B"])
        #expect(lower.notStarted.isEmpty)
    }
}
