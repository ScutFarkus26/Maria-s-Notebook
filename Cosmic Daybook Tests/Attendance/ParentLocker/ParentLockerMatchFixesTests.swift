import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// One ParentLocker child is never matched to two notebook children, and the
/// guide's "Not matched" sticks (bug check 2026-10-13, A2/C4); a save reply's
/// `error` is read the way the site means it (A5). Made-up children, against
/// the recorded rosters (`ParentLockerFixtures`).
@Suite("ParentLocker matching fixes")
@MainActor
struct ParentLockerMatchFixesTests {

    typealias Planner = ParentLockerPlanner
    typealias Child = ParentLockerPlanner.Child

    private let day: Date
    private let rosters: [ParentLockerRoster]

    init() throws {
        day = try CoreDataTestHelpers.day("2026-10-12")
        rosters = try ParentLockerFixtures.rosters()
    }

    private static let sick = Planner.DayMark(statusRaw: AttendanceStatus.absent.rawValue, absenceReasonRaw: "sick")

    private func plan(_ children: [Child]) -> Planner.Plan {
        Planner.plan(
            children: children,
            marks: Dictionary(uniqueKeysWithValues: children.map { ($0.id, Self.sick) }),
            rosters: rosters, day: day
        )
    }

    private func problems(_ plan: Planner.Plan, _ children: [Child]) -> [String] {
        ParentLockerStatus.problems(
            for: plan.skipped,
            names: { id in children.first { $0.id == id }.map(\.firstName) ?? "?" },
            isGuide: true
        )
    }

    // MARK: - "Not matched" sticks

    @Test("\"Not matched\" is never matched by name, sends nothing and asks for nothing")
    func notMatchedSticks() {
        let wren = Child(id: UUID(), firstName: "Wren", lastName: "Halloway", parentLockerID: Planner.notMatchedID)
        #expect(Planner.match(children: [wren], rosters: rosters)[wren.id] == .leftOut)
        let result = plan([wren])
        #expect(result.batches.isEmpty)
        #expect(result.newMatches.isEmpty)
        #expect(result.skipped == [.init(childID: wren.id, reason: .leftOut)])
        #expect(problems(result, [wren]).isEmpty, "a child the guide left out isn't 'not matched yet'")
    }

    @Test("Two children left out aren't ambiguous with each other")
    func twoLeftOut() {
        let wren = Child(id: UUID(), firstName: "Wren", lastName: "Halloway", parentLockerID: "none")
        let june = Child(id: UUID(), firstName: "Juniper", lastName: "Ashby", parentLockerID: " none ")
        let matches = Planner.match(children: [wren, june], rosters: rosters)
        #expect(matches[wren.id] == .leftOut)
        #expect(matches[june.id] == .leftOut)
        #expect(problems(plan([wren, june]), [wren, june]).isEmpty)
    }

    // MARK: - One ParentLocker child, two of ours

    @Test("A stored ID held by two children makes both ambiguous, and neither is sent")
    func storedTwice() {
        let wren = Child(id: UUID(), firstName: "Wren", lastName: "Halloway", parentLockerID: "40001")
        let copy = Child(id: UUID(), firstName: "Renata", lastName: "Hall", parentLockerID: "40001")
        let matches = Planner.match(children: [wren, copy], rosters: rosters)
        #expect(matches[wren.id] == .ambiguous(["40001"]))
        #expect(matches[copy.id] == .ambiguous(["40001"]))
        let result = plan([wren, copy])
        #expect(result.batches.isEmpty)
        #expect(result.upToDate.isEmpty)
        #expect(Set(result.skipped.map(\.childID)) == [wren.id, copy.id])
        #expect(problems(result, [wren, copy]).first?.hasPrefix("2 children aren't matched") == true)
    }

    @Test("An ID held twice is taken out of name matching too")
    func storedTwiceStillTaken() {
        let first = Child(id: UUID(), firstName: "Odile", lastName: "Brandt", parentLockerID: "40001")
        let second = Child(id: UUID(), firstName: "Saoirse", lastName: "Quill", parentLockerID: "40001")
        let byName = Child(id: UUID(), firstName: "Wren", lastName: "Halloway")
        #expect(Planner.match(children: [first, second, byName], rosters: rosters)[byName.id] == .unmatched)
    }

    @Test("What ParentLocker held goes to no child when two claim one ParentLocker child")
    func seenNeverOverwrites() {
        let first = UUID()
        let second = UUID()
        let only = UUID()
        let seen = Planner.seen(
            matches: [
                first: .matched(studentID: "40001", byName: false),
                second: .matched(studentID: "40001", byName: false),
                only: .matched(studentID: "40002", byName: true)
            ],
            rosters: rosters
        )
        #expect(seen[first] == nil)
        #expect(seen[second] == nil)
        #expect(seen[only] != nil)
    }

    // MARK: - Match Names

    @Test("Match Names: left out reads Not matched and needs nothing; ambiguous and unmatched need the guide")
    func matchNamesRows() {
        let leftOut = Child(id: UUID(), firstName: "Wren", lastName: "Halloway", parentLockerID: "none")
        let stored = Child(id: UUID(), firstName: "Juniper", lastName: "Ashby", parentLockerID: "40002")
        let twiceA = Child(id: UUID(), firstName: "Odile", lastName: "Brandt", parentLockerID: "40003")
        let twiceB = Child(id: UUID(), firstName: "Saoirse", lastName: "Quill", parentLockerID: "40003")
        let stranger = Child(id: UUID(), firstName: "Clementine", lastName: "Voss")
        let children = [leftOut, stored, twiceA, twiceB, stranger]
        let rows = ParentLockerMatchView.rows(
            children: children, matches: Planner.match(children: children, rosters: rosters), name: { _ in "x" }
        )
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        #expect(byID[leftOut.id]?.studentID == Planner.notMatchedID)
        #expect(byID[leftOut.id]?.needsYou == false)
        #expect(byID[stored.id]?.studentID == "40002")
        #expect(byID[stored.id]?.needsYou == false)
        #expect(byID[twiceA.id]?.studentID == nil)
        #expect(byID[twiceA.id]?.needsYou == true)
        #expect(byID[twiceB.id]?.needsYou == true)
        #expect(byID[stranger.id]?.needsYou == true)
    }

    @Test("A pick clears that ParentLocker child from whoever held it; Not matched is stored")
    func pickClearsOtherHolder() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let wren = CoreDataTestHelpers.seedStudent(in: context, firstName: "Wren", lastName: "Halloway")
        let june = CoreDataTestHelpers.seedStudent(in: context, firstName: "Juniper", lastName: "Ashby")
        let odile = CoreDataTestHelpers.seedStudent(in: context, firstName: "Odile", lastName: "Brandt")
        wren.parentLockerID = "40001"
        odile.parentLockerID = "40002"
        try context.save()
        let store = ParentLockerCoreDataStore(context: context)

        #expect(store.writeMatches([try #require(june.id): "40001"]))
        #expect(june.parentLockerID == "40001")
        #expect(wren.parentLockerID == nil, "the pick moved 40001 from Wren to June")
        #expect(odile.parentLockerID == "40002", "nobody else is touched")

        #expect(store.writeMatches([try #require(odile.id): Planner.notMatchedID]))
        #expect(odile.parentLockerID == Planner.notMatchedID)
        #expect(june.parentLockerID == "40001", "Not matched clears nobody else")
    }

    @Test("The fake notebook moves a pick the same way")
    func fakePickClearsOtherHolder() {
        let wren = Child(id: UUID(), firstName: "Wren", lastName: "Halloway", parentLockerID: "40001")
        let june = Child(id: UUID(), firstName: "Juniper", lastName: "Ashby")
        let store = FakeParentLockerStore(state: ParentLockerDay(children: [wren, june]))
        #expect(store.writeMatches([june.id: "40001"]))
        let held = Dictionary(uniqueKeysWithValues: store.state.children.map { ($0.id, $0.parentLockerID) })
        #expect(held[june.id] == "40001")
        #expect(held[wren.id] == .some(nil))
        #expect(store.writtenMatches == [[june.id: "40001"]])
    }

    // MARK: - A reply's error (A5)

    @Test("A non-zero number is an error; zero, false and an empty list or object are not")
    func errorValues() throws {
        typealias JSON = ParentLockerJSON
        #expect(ParentLockerRoster.errorText(.int(1)) != nil)
        #expect(ParentLockerRoster.errorText(.int(-2)) != nil)
        #expect(ParentLockerRoster.errorText(.double(1)) != nil)
        #expect(ParentLockerRoster.errorText(.int(0)) == nil)
        #expect(ParentLockerRoster.errorText(.double(0)) == nil)
        #expect(ParentLockerRoster.errorText(.bool(false)) == nil)
        #expect(ParentLockerRoster.errorText(.null) == nil)
        #expect(ParentLockerRoster.errorText(.array([])) == nil)
        #expect(ParentLockerRoster.errorText(.object([:])) == nil)
        #expect(ParentLockerRoster.errorText(.array([.string("Locked")])) != nil)
        #expect(ParentLockerRoster.errorText(.object(["message": .string("No")])) != nil)

        #expect(throws: ParentLockerError.self) {
            try ParentLockerSaveReply(reply: .object(["error": .int(1)]))
        }
        let quiet = try ParentLockerSaveReply(reply: .object(["error": .array([]), "conflicts": .array([])]))
        #expect(quiet.conflicts.isEmpty)
    }
}
