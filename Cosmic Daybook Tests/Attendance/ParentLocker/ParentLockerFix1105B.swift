import Foundation
import Testing
@testable import CosmicDaybook

/// The wire, planner and status wording fixes from the bug hunt
/// "ParentLocker in the Assistant bug hunt 2026-11-05" (fix agent B): marks
/// the page doesn't have (#4), "up to date" with problems (#8), the Notes box
/// (#10), a roster child with no attendance row (#12), a conflict whose ids
/// can't be read (#23), and the smaller #25 items (names, the time text).
@Suite("ParentLocker fixes 2026-11-05 B")
@MainActor
struct ParentLockerFix1105B {

    typealias Planner = ParentLockerPlanner
    typealias Child = ParentLockerPlanner.Child
    typealias DayMark = ParentLockerPlanner.DayMark

    private let day: Date

    init() throws {
        day = try CoreDataTestHelpers.day("2026-10-12")
    }

    private static let marks = [
        ParentLockerMark(id: "701", name: "Present", type: "present"),
        ParentLockerMark(id: "702", name: "Late", type: "late"),
        ParentLockerMark(id: "703", name: "Absent", type: "absent")
    ]

    private static let course = ParentLockerCourse(
        courseID: 5101, name: "Girls Middle School", period: 1, attendanceReportID: "880001"
    )

    /// A child matched by id, and their roster row with `attendance` as sent.
    private static func row(
        _ studentID: Int, attendance: ParentLockerJSON?
    ) throws -> (child: Child, student: ParentLockerRosterStudent) {
        let child = Child(id: UUID(), firstName: "Child", lastName: "\(studentID)", parentLockerID: "\(studentID)")
        var fields: [String: ParentLockerJSON] = [
            "student_id": .int(studentID), "first_name": .string("Child"), "last_name": .string("\(studentID)")
        ]
        if let attendance { fields["attendance"] = attendance }
        return (child, try #require(ParentLockerRosterStudent(json: .object(fields))))
    }

    /// A saved row holding `mark` with `comment` in the Notes box.
    private static func savedRow(
        _ studentID: Int, mark: String, comment: String
    ) throws -> (child: Child, student: ParentLockerRosterStudent) {
        try row(studentID, attendance: .object([
            "attendance_code_id": .string(mark), "attendance_code": .object(["id": .string(mark)]),
            "comment": .string(comment), "confirmed": .bool(true)
        ]))
    }

    private static func absent(_ reason: AbsenceReason) -> DayMark {
        DayMark(statusRaw: AttendanceStatus.absent.rawValue, absenceReasonRaw: reason.rawValue)
    }

    /// `ownNotes`: what this device wrote in each child's box earlier today.
    private func plan(
        _ rows: [(child: Child, student: ParentLockerRosterStudent)], marks: [UUID: DayMark],
        ownNotes: [UUID: Set<String>] = [:]
    ) -> Planner.Plan {
        let roster = ParentLockerRoster(course: Self.course, students: rows.map(\.student), marks: Self.marks)
        return Planner.plan(
            children: rows.map(\.child), marks: marks, rosters: [roster], day: day,
            ownNotes: ownNotes.mapValues { [Self.course.courseID: $0] }
        )
    }

    // MARK: - #10: the Notes box

    @Test("A reason never replaces a parent's or the office's words in the Notes box")
    func parentsNoteKept() throws {
        // Already Absent with the parent's words: nothing to send.
        let alreadyAbsent = try Self.savedRow(50001, mark: "703", comment: "Mom emailed: strep, back Thu")
        // Present before: the mark goes, the box stays.
        let wasPresent = try Self.savedRow(50002, mark: "701", comment: "Grandma picking up at 2")
        let plan = plan([alreadyAbsent, wasPresent], marks: [
            alreadyAbsent.child.id: Self.absent(.sick), wasPresent.child.id: Self.absent(.appointment)
        ])

        #expect(plan.upToDate == [alreadyAbsent.child.id])
        let entry = try #require(plan.batches.first?.entries.first)
        #expect(plan.batches.first?.entries.count == 1)
        #expect(entry.childID == wasPresent.child.id)
        #expect(entry.type == .absent)
        #expect(entry.comment == nil)
        #expect(entry.attendance["comment"] == .string("Grandma picking up at 2"))
    }

    @Test("The app's note goes in an empty box or over its own earlier note")
    func appNoteWritten() throws {
        let empty = try Self.savedRow(50003, mark: "701", comment: "")
        let blank = try Self.savedRow(50004, mark: "701", comment: "  ")
        let ownEarlier = try Self.savedRow(50005, mark: "703", comment: "Appointment")
        // The same word, which this device never wrote: the office's (review of the 2026-11-05 fixes, W3).
        let theirs = try Self.savedRow(50007, mark: "703", comment: "Appointment")
        let plan = plan([empty, blank, ownEarlier, theirs], marks: [
            empty.child.id: Self.absent(.sick), blank.child.id: Self.absent(.family),
            ownEarlier.child.id: Self.absent(.sick), theirs.child.id: Self.absent(.sick)
        ], ownNotes: [ownEarlier.child.id: ["Appointment"]])
        let sent = Dictionary(uniqueKeysWithValues: (plan.batches.first?.entries ?? []).map { ($0.childID, $0) })
        #expect(sent[empty.child.id]?.comment == "Sick")
        #expect(sent[blank.child.id]?.comment == "Family")
        #expect(sent[ownEarlier.child.id]?.comment == "Sick")
        #expect(sent[ownEarlier.child.id]?.type == .absent)
        #expect(sent[theirs.child.id] == nil)
        #expect(plan.upToDate.contains(theirs.child.id))
    }

    @Test("A left-early line never replaces someone's words")
    func leftEarlyKeepsTheirWords() throws {
        let theirs = try Self.savedRow(50006, mark: "701", comment: "Dentist, mom will sign out")
        let leftAt = Date(timeIntervalSince1970: 1_791_811_800)
        let mark = DayMark(statusRaw: AttendanceStatus.leftEarly.rawValue, leftAt: leftAt,
                           statusBeforeLeavingRaw: AttendanceStatus.present.rawValue)
        let plan = plan([theirs], marks: [theirs.child.id: mark])
        #expect(plan.batches.isEmpty)
        #expect(plan.upToDate == [theirs.child.id])
    }

    @Test("Only the app's exact left-early lines count as its notes")
    func leftEarlyExactly() {
        // Plain "Left early" counts only when this device wrote it (review of the 2026-11-05 fixes, W3).
        #expect(!Planner.isAppNote("Left early"))
        #expect(Planner.isAppNote("Left early", wrote: ["Left early"]))
        #expect(Planner.isAppNote("Left early at 1:30 PM"))
        #expect(Planner.isAppNote("Left early at 11:05 AM"))
        // What earlier builds wrote: the system's narrow space, or a two-digit 24-hour clock.
        #expect(Planner.isAppNote("Left early at 1:30\u{202F}PM"))
        #expect(Planner.isAppNote("Left early at 13:30"))
        for theirs in [
            "Left early for the dentist", "Left early at the dentist's request", "Left early at 1:30 PM with Dad",
            "Left early, back tomorrow", "Left earlyish", "left early at 1:30 PM"
        ] {
            #expect(!Planner.isAppNote(theirs), "\(theirs)")
        }
    }

    // MARK: - #25: the left-early time

    @Test("The left-early time is h:mm AM/PM with a plain space, whatever the device's locale")
    func fixedTimeText() throws {
        let leftAt = Date(timeIntervalSince1970: 1_791_811_800)
        let text = Planner.defaultTimeText(leftAt)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "h:mm a"
        #expect(text == formatter.string(from: leftAt))
        #expect(!text.contains("\u{202F}"))
        #expect(text.range(of: #"^(1[0-2]|[1-9]):[0-5][0-9] (AM|PM)$"#, options: .regularExpression) != nil)
        #expect(Planner.isAppNote("Left early at \(text)"))
    }

    // MARK: - #25: names

    @Test("Hyphens and curly apostrophes don't stop a name matching")
    func hyphensAndApostrophes() throws {
        let benDavid = try #require(ParentLockerRosterStudent(json: .object([
            "student_id": .int(1), "first_name": .string("Noa"), "last_name": .string("Ben David")
        ])))
        let oneil = try #require(ParentLockerRosterStudent(json: .object([
            "student_id": .int(2), "first_name": .string("Shira"), "last_name": .string("O'Neil")
        ])))
        #expect(Planner.namesFit(Child(id: UUID(), firstName: "Noa", lastName: "Ben-David"), benDavid))
        #expect(Planner.namesFit(Child(id: UUID(), firstName: "Noa", lastName: "Ben\u{2011}David"), benDavid))
        #expect(Planner.namesFit(Child(id: UUID(), firstName: "Shira", lastName: "O\u{2019}Neil"), oneil))
        #expect(!Planner.namesFit(Child(id: UUID(), firstName: "Noa", lastName: "Bendavid"), benDavid))
    }

    // MARK: - #12: no attendance row

    @Test("A roster child whose attendance is null or empty is skipped with a plain line")
    func noAttendanceRow() throws {
        let null = try Self.row(50010, attendance: .null)
        let empty = try Self.row(50011, attendance: .array([]))
        let missing = try Self.row(50012, attendance: nil)
        let rows = [null, empty, missing]
        let plan = plan(rows, marks: Dictionary(uniqueKeysWithValues: rows.map {
            ($0.child.id, DayMark(statusRaw: AttendanceStatus.present.rawValue))
        }))

        #expect(plan.batches.isEmpty, "no save with no ids")
        #expect(plan.upToDate.isEmpty)
        let names: [UUID: String] = [null.child.id: "Maya S", empty.child.id: "Ari B", missing.child.id: "Tova K"]
        let lines = ParentLockerStatus.problems(for: plan.skipped, names: { names[$0] ?? "?" }, isGuide: false)
        #expect(lines.count == 1)
        let line = try #require(lines.first)
        #expect(line.contains("Maya S") && line.contains("Ari B") && line.contains("Tova K"))
        #expect(line.contains("ParentLocker site"))
        #expect(!line.contains("null") && !line.contains("attendance_"))
    }

    // MARK: - #4: marks the page doesn't have

    @Test("Marks the school's page doesn't have leave a standing line naming the mark and the children")
    func missingMarkLine() {
        let maya = UUID(), ari = UUID(), tova = UUID()
        let names = [maya: "Maya S", ari: "Ari B", tova: "Tova K"]
        let skipped = [
            Planner.Skip(childID: maya, reason: .noSuchMark(.late)),
            Planner.Skip(childID: ari, reason: .noSuchMark(.late)),
            Planner.Skip(childID: tova, reason: .noSuchMark(.absent))
        ]
        let lines = ParentLockerStatus.problems(for: skipped, names: { names[$0] ?? "?" }, isGuide: true)
        #expect(lines == [
            "Late marks couldn't go for Maya S and Ari B: ParentLocker has no Late mark right now. " +
                "Mark them on the ParentLocker site.",
            "Absent marks couldn't go for Tova K: ParentLocker has no Absent mark right now. " +
                "Mark Tova K on the ParentLocker site."
        ])
    }

    // MARK: - #8: "up to date" with problems

    @Test("With problems, the line never says up to date, and its symbol is the warning one")
    func noUpToDateWithProblems() {
        let problem = "The office already marked Maya S Absent."
        let status = ParentLockerStatus(state: .upToDate, problems: [problem])
        let sent = "Sent to ParentLocker 8:47 AM by Sarah"

        for line in [status.line(sentSummary: sent), status.line(sentSummary: nil), status.message] {
            let text = line ?? ""
            #expect(!text.isEmpty)
            #expect(!text.lowercased().contains("up to date"), "\(text)")
        }
        #expect(status.line(sentSummary: sent)?.hasPrefix(sent) == true)
        #expect(status.isTrouble)
        #expect(ParentLockerStatusLine.symbol(for: status) == "exclamationmark.triangle")
        // The compact row (the Assistant's bar) draws the same line without the children's lines.
        let compact = ParentLockerStatusLine.content(for: status, sentSummary: sent, showsProblems: false)
        #expect(compact?.line?.lowercased().contains("up to date") == false)

        // With none, it still does.
        let clean = ParentLockerStatus(state: .upToDate)
        #expect(clean.line(sentSummary: sent) == sent + " · up to date")
        #expect(clean.message == "Up to date in ParentLocker.")
        #expect(ParentLockerStatusLine.symbol(for: clean) == "checkmark.circle")
    }

    // MARK: - #23: conflicts

    @Test("A conflict whose ids can't be read counts as a real conflict")
    func unreadableConflict() throws {
        let blank = ParentLockerSaveReply.Conflict(studentID: "40001", desiredMarkID: nil, currentMarkID: nil)
        #expect(!blank.alreadyEqual)
        let reply = try ParentLockerSaveReply(reply: .object([
            "conflicts": .array([.object(["student_id": .int(40001), "desired": .object([:]), "current": .null])])
        ]))
        #expect(reply.conflicts.map(\.alreadyEqual) == [false])
        #expect(ParentLockerSaveReply.Conflict(studentID: "1", desiredMarkID: "702", currentMarkID: "702").alreadyEqual)
    }

    // MARK: - Wire leftovers: PHP keyed arrays

    @Test("Lists PHP sends as keyed objects are read as lists, in key order")
    func keyedArrays() throws {
        func student(_ id: Int, _ first: String) -> ParentLockerJSON {
            .object([
                "student_id": .int(id), "first_name": .string(first), "last_name": .string("Lee"),
                "attendance": .object(["comment": .string(""), "confirmed": .bool(false)])
            ])
        }
        let roster = try ParentLockerRoster(reply: .object([
            "students": .object(["10": student(3, "Cy"), "2": student(2, "Bo"), "1": student(1, "Al")]),
            "attendance_settings": .object([
                "0": .object(["id": .string("701"), "name": .string("Present"), "type": .string("present")]),
                "1": .object(["id": .string("702"), "name": .string("Late"), "type": .string("late")])
            ])
        ]), course: Self.course)
        #expect(roster.students.map(\.firstName) == ["Al", "Bo", "Cy"])
        #expect(roster.marks.map(\.id) == ["701", "702"])

        let reply = try ParentLockerSaveReply(reply: .object([
            "conflicts": .object(["0": .object([
                "student_id": .int(1), "desired": .object(["attendance_code_id": .string("701")]),
                "current": .object(["attendance_code_id": .string("703")])
            ])])
        ]))
        #expect(reply.conflicts.map(\.studentID) == ["1"])
    }

    // MARK: - Wire leftovers: a period that isn't a number

    @Test("Two classes told apart only by a period that isn't a number are both kept")
    func textPeriods() throws {
        let html = """
            <script>
            var courses = [{"course_id": 6001, "course_name": "Art", "period": "A", "attendance_report_id": "9001", \
            "isDailyAttendance": 1, "hasAttendance": 1}, {"course_id": 6001, "course_name": "Art", "period": "B", \
            "attendance_report_id": "9002", "isDailyAttendance": 1, "hasAttendance": 1}];
            </script>
            """
        let courses = try #require(ParentLockerCourse.courses(inPage: html))
        #expect(courses.map(\.attendanceReportID) == ["9001", "9002"])
    }
}
