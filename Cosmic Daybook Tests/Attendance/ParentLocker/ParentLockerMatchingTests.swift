import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// Which ParentLocker child each notebook child is, against the recorded
/// rosters (`ParentLockerFixtures`), and the marks read from the store.
/// A wrong match would send one child's mark to another, so only a match
/// where exactly one child fits on both sides counts.
@Suite("ParentLocker name matching")
@MainActor
struct ParentLockerMatchingTests {

    typealias Planner = ParentLockerPlanner
    typealias Child = ParentLockerPlanner.Child

    private let rosters: [ParentLockerRoster]

    init() throws {
        rosters = try ParentLockerFixtures.rosters()
    }

    private func match(_ children: [Child]) -> [UUID: Planner.Match] {
        Planner.match(children: children, rosters: rosters)
    }

    @Test("Case, accents and extra spaces don't count")
    func caseAndAccents() {
        let marisol = Child(id: UUID(), firstName: " MARISOL", lastName: "pena ")
        let wren = Child(id: UUID(), firstName: "wren", lastName: "HALLOWAY")
        let result = match([marisol, wren])
        #expect(result[marisol.id] == .matched(studentID: "40003", byName: true))
        #expect(result[wren.id] == .matched(studentID: "40001", byName: true))
    }

    @Test("A nickname matches ParentLocker's alternate name, and a first name its first name")
    func nicknameAgainstAlternate() {
        let byNickname = Child(id: UUID(), firstName: "Jun", lastName: "Ashby", nickname: "June")
        let byFirst = Child(id: UUID(), firstName: "Juniper", lastName: "Ashby")
        #expect(match([byNickname])[byNickname.id] == .matched(studentID: "40002", byName: true))
        #expect(match([byFirst])[byFirst.id] == .matched(studentID: "40002", byName: true))
    }

    @Test("The same first name twice is told apart by last name")
    func sameFirstNameTwice() {
        let halloway = Child(id: UUID(), firstName: "Wren", lastName: "Halloway")
        let calloway = Child(id: UUID(), firstName: "Wren", lastName: "Calloway")
        let result = match([halloway, calloway])
        #expect(result[halloway.id] == .matched(studentID: "40001", byName: true))
        #expect(result[calloway.id] == .matched(studentID: "41001", byName: true))
    }

    @Test("Two ParentLocker children who fit one of ours: ambiguous, nobody matched")
    func twoOnTheirSide() {
        let ada = Child(id: UUID(), firstName: "Ada", lastName: "Fern")
        #expect(match([ada])[ada.id] == .ambiguous(["40004", "40005"]))
    }

    @Test("One ParentLocker child who fits two of ours: ambiguous for both")
    func twoOnOurSide() {
        let first = Child(id: UUID(), firstName: "Wren", lastName: "Halloway")
        let second = Child(id: UUID(), firstName: "Wren", lastName: "Halloway", nickname: "Renny")
        let result = match([first, second])
        #expect(result[first.id] == .ambiguous(["40001"]))
        #expect(result[second.id] == .ambiguous(["40001"]))
    }

    @Test("No one who fits: unmatched; a different last name never fits")
    func unmatched() {
        let stranger = Child(id: UUID(), firstName: "Clementine", lastName: "Voss")
        let wrongLast = Child(id: UUID(), firstName: "Wren", lastName: "Hollaway")
        let result = match([stranger, wrongLast])
        #expect(result[stranger.id] == .unmatched)
        #expect(result[wrongLast.id] == .unmatched)
    }

    @Test("A stored match goes by ID, and takes that child out of name matching")
    func storedMatchWins() {
        let renamed = Child(id: UUID(), firstName: "Renata", lastName: "Hall", parentLockerID: "40001")
        let sameName = Child(id: UUID(), firstName: "Wren", lastName: "Halloway")
        let result = match([renamed, sameName])
        #expect(result[renamed.id] == .matched(studentID: "40001", byName: false))
        #expect(result[sameName.id] == .unmatched)
    }

    @Test("A stored match no roster holds is unmatched, not matched again by name")
    func storedMatchMissing() {
        let gone = Child(id: UUID(), firstName: "Wren", lastName: "Halloway", parentLockerID: "99999")
        #expect(match([gone])[gone.id] == .unmatched)
    }

    // MARK: - Reading the store

    @Test("A day's marks come from the record that wins among duplicates")
    func duplicateUsesWinner() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let day = try CoreDataTestHelpers.day("2026-10-12")
        let childID = UUID()
        let other = UUID()
        let morning = day.addingTimeInterval(8 * 3600)

        let older = CDAttendanceRecord(context: ctx)
        older.studentID = childID.uuidString
        older.date = day
        older.status = .present
        older.modifiedAt = morning
        let newer = CDAttendanceRecord(context: ctx)
        newer.studentID = childID.uuidString
        newer.date = day
        newer.status = .absent
        newer.absenceReason = .sick
        newer.modifiedAt = morning.addingTimeInterval(600)
        // Close Arrival's absence loses to a real mark, even a later one.
        let automatic = CDAttendanceRecord(context: ctx)
        automatic.studentID = other.uuidString
        automatic.date = day
        automatic.status = .absent
        automatic.absenceReasonRaw = AttendanceDeduplication.automaticAbsenceRaw
        automatic.modifiedAt = morning.addingTimeInterval(900)
        let real = CDAttendanceRecord(context: ctx)
        real.studentID = other.uuidString
        real.date = day
        real.status = .tardy
        real.modifiedAt = morning
        #expect(CoreDataTestHelpers.save(ctx))

        let marks = Planner.dayMarks(on: day.addingTimeInterval(3600), in: ctx)
        #expect(marks[childID] == .init(statusRaw: "absent", absenceReasonRaw: "sick"))
        #expect(marks[other]?.statusRaw == "tardy")
        #expect(Planner.dayMarks(on: day, for: [other], in: ctx).keys.sorted() == [other])
    }

    @Test("A notebook student becomes a child to match, with the stored ID")
    func childFromStudent() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let student = CDStudent(context: ctx)
        student.firstName = "Juniper"
        student.lastName = "Ashby"
        student.nickname = "June"
        student.parentLockerID = "40002"
        let child = try #require(Child(student))
        #expect(child.id == student.id)
        #expect(child.nickname == "June")
        #expect(child.parentLockerID == "40002")
    }
}
