import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// What the app would send to ParentLocker for a day, worked out against the
/// recorded rosters (`ParentLockerFixtures`): the mark each child's day maps
/// to, which ParentLocker child each notebook child is, and which children
/// differ, one save per class.
@Suite("ParentLocker planner")
@MainActor
struct ParentLockerPlannerTests {

    typealias Planner = ParentLockerPlanner
    typealias Child = ParentLockerPlanner.Child
    typealias DayMark = ParentLockerPlanner.DayMark

    // MARK: - Children

    private static let wren = Child(id: UUID(), firstName: "Wren", lastName: "Halloway")
    /// Goes by June; ParentLocker has her as Juniper with the alternate name June.
    private static let june = Child(id: UUID(), firstName: "Jun", lastName: "Ashby", nickname: "June")
    /// Her name typed without the accent, in capitals, with extra spaces.
    private static let marisol = Child(id: UUID(), firstName: "MARISOL ", lastName: "  Pena")
    /// ParentLocker has two children of this name.
    private static let ada = Child(id: UUID(), firstName: "Ada", lastName: "Fern")
    private static let tamsin = Child(id: UUID(), firstName: "Tamsin", lastName: "Okafor")
    /// The other Wren, in the other class.
    private static let wrenCalloway = Child(id: UUID(), firstName: "Wren", lastName: "Calloway")
    private static let odile = Child(id: UUID(), firstName: "Odile", lastName: "Brandt")
    private static let saoirse = Child(id: UUID(), firstName: "Saoirse", lastName: "Quill")
    /// Matched before, so by ID.
    private static let bea = Child(id: UUID(), firstName: "Beatrice", lastName: "M", parentLockerID: "41004")
    /// Not on ParentLocker at all.
    private static let clementine = Child(id: UUID(), firstName: "Clementine", lastName: "Voss")

    private static let everyone = [wren, june, marisol, ada, tamsin, wrenCalloway, odile, saoirse, bea, clementine]

    private let day: Date
    private let rosters: [ParentLockerRoster]

    init() throws {
        day = try CoreDataTestHelpers.day("2026-10-12")
        rosters = try ParentLockerFixtures.rosters()
    }

    /// "1:30 PM" for 13:30 UTC, whatever this machine's zone and locale.
    private static func utcTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private nonisolated static let leftAt = Date(timeIntervalSince1970: 1_791_811_800) // 2026-10-12 13:30 UTC

    private nonisolated static func mark(
        _ status: AttendanceStatus, reason: String = "none", leftAt: Date? = nil, before: AttendanceStatus? = nil
    ) -> DayMark {
        DayMark(statusRaw: status.rawValue, absenceReasonRaw: reason, leftAt: leftAt,
                statusBeforeLeavingRaw: before?.rawValue)
    }

    private func plan(_ marks: [UUID: DayMark], only: Set<UUID>? = nil) -> Planner.Plan {
        Planner.plan(children: Self.everyone, marks: marks, rosters: rosters, only: only,
                     day: day, timeText: Self.utcTime)
    }

    // MARK: - Mark mapping

    struct MappingCase: Sendable, CustomTestStringConvertible {
        let name: String
        let mark: DayMark?
        let wanted: Planner.Wanted
        var testDescription: String { name }
    }

    nonisolated static let mappings: [MappingCase] = [
        .init(name: "Here", mark: mark(.present), wanted: .send(.present, comment: nil)),
        .init(name: "Late, with no arrival time", mark: mark(.tardy), wanted: .send(.late, comment: nil)),
        .init(name: "Absent, sick", mark: mark(.absent, reason: "sick"), wanted: .send(.absent, comment: "Sick")),
        .init(name: "Absent, appointment", mark: mark(.absent, reason: "appointment"),
              wanted: .send(.absent, comment: "Appointment")),
        .init(name: "Absent, vacation", mark: mark(.absent, reason: "vacation"),
              wanted: .send(.absent, comment: "Vacation")),
        .init(name: "Absent, family", mark: mark(.absent, reason: "family"),
              wanted: .send(.absent, comment: "Family")),
        .init(name: "Absent, other", mark: mark(.absent, reason: "other"), wanted: .send(.absent, comment: "Other")),
        .init(name: "Absent, no reason: Notes left alone", mark: mark(.absent), wanted: .send(.absent, comment: nil)),
        .init(name: "Close Arrival's absence: an empty Notes box", mark: mark(.absent, reason: "closeArrival"),
              wanted: .send(.absent, comment: "")),
        .init(name: "Left early after arriving on time", mark: mark(.leftEarly, leftAt: leftAt, before: .present),
              wanted: .send(.present, comment: "Left early at 1:30 PM")),
        .init(name: "Left early after arriving late", mark: mark(.leftEarly, leftAt: leftAt, before: .tardy),
              wanted: .send(.late, comment: "Left early at 1:30 PM")),
        .init(name: "Left early with no time", mark: mark(.leftEarly), wanted: .send(.present, comment: "Left early")),
        .init(name: "Unmarked", mark: mark(.unmarked), wanted: .nothing),
        .init(name: "No record", mark: nil, wanted: .nothing),
        .init(name: "A mark from a newer build", mark: DayMark(statusRaw: "onTrip"), wanted: .unknown)
    ]

    @Test("Each mark maps to what ParentLocker is sent", arguments: mappings)
    func markMapping(_ item: MappingCase) {
        #expect(Planner.wanted(for: item.mark, timeText: Self.utcTime) == item.wanted)
    }

    @Test("The Notes box words a reason as the screens do")
    func reasonWords() {
        for reason in AbsenceReason.given {
            #expect(Planner.reasonText(reason) == reason.displayName)
        }
        #expect(Planner.reasonText(.none) == nil)
    }

    @Test("Dates are written YYYY-M-D, with no leading zeros")
    func dateText() throws {
        #expect(Planner.dateText(try CoreDataTestHelpers.day("2026-03-05")) == "2026-3-5")
        #expect(Planner.dateText(try CoreDataTestHelpers.day("2026-10-12")) == "2026-10-12")
    }

    @Test("The school's marks are found by type, skipping deleted ones and hidden ones first")
    func marksByType() throws {
        let marks = try #require(rosters.first).marks
        #expect(ParentLockerMark.find(.present, in: marks)?.id == "701")
        #expect(ParentLockerMark.find(.late, in: marks)?.id == "702")
        #expect(ParentLockerMark.find(.absent, in: marks)?.id == "703")
    }

    // MARK: - A whole day

    /// A whole day across both classes.
    private func wholeDayPlan() -> Planner.Plan {
        let marks: [UUID: DayMark] = [
            Self.wren.id: Self.mark(.present),
            Self.june.id: Self.mark(.tardy),
            Self.marisol.id: Self.mark(.present),
            Self.ada.id: Self.mark(.absent, reason: "sick"),
            Self.tamsin.id: Self.mark(.present),
            Self.wrenCalloway.id: Self.mark(.absent, reason: "closeArrival"),
            Self.saoirse.id: Self.mark(.present),
            Self.bea.id: Self.mark(.leftEarly, leftAt: Self.leftAt, before: .tardy),
            Self.clementine.id: Self.mark(.present)
        ]
        return plan(marks)
    }

    @Test("A class's day: one save per class, only the children who differ")
    func wholeDay() throws {
        let plan = wholeDayPlan()

        #expect(plan.batches.count == 2)
        let middle = try #require(plan.batches.first { $0.course.courseID == 5101 })
        #expect(middle.attendanceReportID == "880001")
        #expect(middle.date == "2026-10-12")
        #expect(middle.entries.map(\.childID) == [Self.wren.id, Self.june.id])
        #expect(middle.entries.map(\.type) == [.present, .late])
        #expect(middle.entries.map(\.studentID) == ["40001", "40002"])

        let upper = try #require(plan.batches.first { $0.course.courseID == 5102 })
        #expect(upper.attendanceReportID == "880002")
        #expect(upper.entries.map(\.childID) == [Self.wrenCalloway.id, Self.saoirse.id, Self.bea.id])
        #expect(upper.entries.map(\.type) == [.absent, .present, .late])
        #expect(upper.entries.map(\.comment) == ["", nil, "Left early at 1:30 PM"])
    }

    @Test("A class's day: who was left alone and why, and the matches to keep")
    func wholeDaySkips() {
        let plan = wholeDayPlan()
        // Marisol is already Present; Saoirse's Present was only expected, so it is sent.
        #expect(plan.upToDate == [Self.marisol.id])
        #expect(plan.skipped.contains(Planner.Skip(childID: Self.odile.id, reason: .cantClear(currentMark: "Present"))))
        #expect(plan.skipped.contains(Planner.Skip(childID: Self.tamsin.id, reason: .locked(currentMark: "Absent"))))
        let adaSkip = Planner.Skip(childID: Self.ada.id, reason: .ambiguous(studentIDs: ["40004", "40005"]))
        #expect(plan.skipped.contains(adaSkip))
        #expect(plan.skipped.contains(Planner.Skip(childID: Self.clementine.id, reason: .unmatched)))

        // Pippa, on ParentLocker but not in the notebook, is never touched.
        #expect(!plan.batches.flatMap(\.entries).contains { $0.studentID == "40007" })
        // Name matches are handed back to store; Bea's stored match isn't new.
        #expect(plan.newMatches[Self.june.id] == "40002")
        #expect(plan.newMatches[Self.marisol.id] == "40003")
        #expect(plan.newMatches[Self.bea.id] == nil)
    }

    @Test("A save echoes the roster's own attendance object, changing only the mark, confirmed and Notes")
    func echoesAttendanceObject() throws {
        let plan = plan([Self.wren.id: Self.mark(.absent, reason: "sick")], only: [Self.wren.id])
        let entry = try #require(plan.batches.first?.entries.first)
        let saved = entry.attendance
        #expect(saved["attendance_code"] == .object([
            "id": .string("703"), "type": .string("absent"), "name": .string("Absent"), "is_excused": .string("0")
        ]))
        #expect(saved["confirmed"] == .bool(true))
        #expect(saved["comment"] == .string("Sick"))
        #expect(saved["student_id"] == .int(40001))
        #expect(saved["course_id"] == .int(5101))
        #expect(saved["in_school"]?["status"] == .string("unknown"))
        #expect(saved["expected_start"] == .string(""))
        #expect(saved["major"] == .string(""))
        #expect(plan.batches.first?.students == [saved])
    }

    @Test("With nothing to say, the Notes box keeps what ParentLocker has")
    func notesLeftAlone() throws {
        let plan = plan([Self.marisol.id: Self.mark(.absent)], only: [Self.marisol.id])
        let entry = try #require(plan.batches.first?.entries.first)
        #expect(entry.comment == nil)
        #expect(entry.attendance["comment"] == .string("bus was late"))
        #expect(entry.attendance["attendance_code"]?["type"] == .string("absent"))
    }

    @Test("A child unmarked here and in ParentLocker is left out quietly")
    func unmarkedSkipped() {
        let plan = plan([:], only: [Self.wren.id])
        #expect(plan.batches.isEmpty)
        #expect(plan.skipped == [.init(childID: Self.wren.id, reason: .unmarked)])
    }

    @Test("Only the children asked about are compared and sent")
    func onlyThoseAsked() throws {
        let plan = plan([Self.wren.id: Self.mark(.present), Self.june.id: Self.mark(.tardy)], only: [Self.june.id])
        #expect(plan.batches.count == 1)
        #expect(plan.batches.first?.entries.map(\.childID) == [Self.june.id])
        #expect(plan.skipped.isEmpty)
    }

    @Test("A mark the school doesn't have is reported, not guessed")
    func missingMark() throws {
        let presentOnly = try #require(rosters.first)
        let roster = ParentLockerRoster(
            course: presentOnly.course, students: presentOnly.students,
            marks: presentOnly.marks.filter { $0.type == "present" }
        )
        let plan = Planner.plan(children: [Self.wren], marks: [Self.wren.id: Self.mark(.tardy)],
                                rosters: [roster], day: day)
        #expect(plan.batches.isEmpty)
        #expect(plan.skipped == [.init(childID: Self.wren.id, reason: .noSuchMark(.late))])
    }

    @Test("A locked row already on our mark counts as up to date")
    func lockedButEqual() {
        let plan = plan([Self.tamsin.id: Self.mark(.absent, reason: "sick")], only: [Self.tamsin.id])
        #expect(plan.batches.isEmpty)
        #expect(plan.upToDate == [Self.tamsin.id])
    }
}

// MARK: - Notes the app wrote before

extension ParentLockerPlannerTests {

    /// A child matched by ID, and their row as ParentLocker holds it.
    private static func row(
        _ studentID: Int, mark: String, comment: String
    ) -> (child: Child, student: ParentLockerRosterStudent?) {
        let child = Child(id: UUID(), firstName: "Child", lastName: "\(studentID)", parentLockerID: "\(studentID)")
        let student = ParentLockerRosterStudent(json: .object([
            "student_id": .int(studentID), "first_name": .string("Child"), "last_name": .string("\(studentID)"),
            "attendance": .object([
                "attendance_code_id": .string(mark), "attendance_code": .object(["id": .string(mark)]),
                "comment": .string(comment), "confirmed": .bool(true)
            ])
        ]))
        return (child, student)
    }

    @Test("A mark with nothing to say clears the box only when it holds what the app wrote")
    func clearsAppNotes() throws {
        let sickThenLate = Self.row(50001, mark: "703", comment: "Sick")
        let backInClass = Self.row(50002, mark: "701", comment: "Left early at 1:30 PM")
        let theirWords = Self.row(50003, mark: "703", comment: "Grandma is visiting")
        let reasonDropped = Self.row(50004, mark: "703", comment: "Appointment")
        let stillSick = Self.row(50005, mark: "703", comment: "Sick")
        let rows = [sickThenLate, backInClass, theirWords, reasonDropped, stillSick]
        let course = ParentLockerCourse(courseID: 5101, name: "Girls Middle School", period: 1, attendanceReportID: "1")
        let roster = ParentLockerRoster(
            course: course, students: rows.compactMap(\.student),
            marks: [
                ParentLockerMark(id: "701", name: "Present", type: "present"),
                ParentLockerMark(id: "702", name: "Late", type: "late"),
                ParentLockerMark(id: "703", name: "Absent", type: "absent")
            ]
        )
        let marks: [UUID: DayMark] = [
            sickThenLate.child.id: Self.mark(.tardy),
            backInClass.child.id: Self.mark(.present),
            theirWords.child.id: Self.mark(.tardy),
            reasonDropped.child.id: Self.mark(.absent),
            stillSick.child.id: Self.mark(.absent, reason: "sick")
        ]
        let plan = Planner.plan(children: rows.map(\.child), marks: marks, rosters: [roster], day: day)
        let entries = try #require(plan.batches.first?.entries)
        let sent = Dictionary(uniqueKeysWithValues: entries.map { ($0.childID, $0) })

        #expect(sent[sickThenLate.child.id]?.comment == "")
        #expect(sent[sickThenLate.child.id]?.attendance["comment"] == .string(""))
        // Back in Class: the same Present, so only the box changes.
        #expect(sent[backInClass.child.id]?.type == .present)
        #expect(sent[backInClass.child.id]?.comment == "")
        #expect(sent[reasonDropped.child.id]?.comment == "")
        // Someone else's words stay.
        #expect(sent[theirWords.child.id]?.comment == nil)
        #expect(sent[theirWords.child.id]?.attendance["comment"] == .string("Grandma is visiting"))
        #expect(sent[stillSick.child.id] == nil)
        #expect(plan.upToDate == [stillSick.child.id])
        #expect(entries.count == 4)
    }

    @Test("Only the app's own words count as its notes: every reason, and a left-early line")
    func appNotes() {
        for reason in AbsenceReason.given {
            #expect(Planner.isAppNote(Planner.reasonText(reason) ?? "-"))
        }
        #expect(Planner.isAppNote("Left early at 1:30 PM"))
        #expect(Planner.isAppNote("Left early"))
        for theirs in ["", "sick", "Sick with a cold", "Other plans", "Picked up by Grandma"] {
            #expect(!Planner.isAppNote(theirs))
        }
    }
}
