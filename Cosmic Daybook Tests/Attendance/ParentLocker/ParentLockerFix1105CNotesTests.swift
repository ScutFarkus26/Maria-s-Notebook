import Foundation
import Testing
@testable import CosmicDaybook

/// Whose words are in the Notes box, as the review of the 2026-11-05 fixes
/// found it (report "ParentLocker in the Assistant bug hunt 2026-11-05",
/// Review of the fixes, W3, W4): the app writes only into an empty box or
/// over its own earlier note, which it knows by what this device wrote for
/// the child, and never clears anyone else's words. With no record, only
/// its unmistakable "Left early at <time>" line counts as its own.
@Suite("ParentLocker fixes 2026-11-05 C: the Notes box")
@MainActor
struct ParentLockerFix1105CNotesTests {

    typealias Planner = ParentLockerPlanner
    typealias Device = ParentLockerTestDevice
    typealias Marks = Fix1105AMarks

    let site = FakeParentLocker()
    let clock = FakeParentLockerClock(Device.morning)

    private static func absent(_ reason: AbsenceReason) -> ParentLockerPlanner.DayMark {
        Device.mark(.absent, reason: reason.rawValue)
    }

    // MARK: - W3 Whose words

    @Test("A one-word note the app has no record of writing is someone else's, and stays (W3)")
    func oneWordNoteStays() {
        for word in ["Sick", "Family", "Appointment", "Vacation", "Other", "Left early"] {
            #expect(!Planner.isAppNote(word), "\(word)")
            #expect(Planner.noteToWrite(nil, over: word) == nil, "\(word)")
            #expect(Planner.noteToWrite("Sick", over: word) == nil, "\(word)")
        }
    }

    @Test("What this device wrote for the child is its own: replaced, or cleared with nothing to say (W3)")
    func ownNoteReplaced() {
        #expect(Planner.isAppNote("Sick", wrote: ["Sick"]))
        #expect(Planner.isAppNote(" Sick ", wrote: ["Sick"]))
        #expect(Planner.noteToWrite("Family", over: "Sick", wrote: ["Sick"]) == "Family")
        #expect(Planner.noteToWrite(nil, over: "Sick", wrote: ["Sick"]) == "")
        #expect(Planner.noteToWrite(nil, over: "Family", wrote: ["Sick"]) == nil, "not what it wrote")
        #expect(Planner.noteToWrite("Sick", over: "  ") == "Sick", "an empty box")
        #expect(!Planner.isAppNote("", wrote: [""]))
        // Its own left-early line needs no record.
        #expect(Planner.noteToWrite(nil, over: "Left early at 1:30 PM") == "")
        #expect(Planner.noteToWrite("Sick", over: "Left early at 1:30 PM") == "Sick")
    }

    @Test("The plan takes each child's own notes, class by class (W3)")
    func planTakesOwnNotes() throws {
        let course = FakeParentLocker.middle
        let ours = Planner.Child(id: UUID(), firstName: "Child", lastName: "50001", parentLockerID: "50001")
        let theirs = Planner.Child(id: UUID(), firstName: "Child", lastName: "50002", parentLockerID: "50002")
        let otherClass = Planner.Child(id: UUID(), firstName: "Child", lastName: "50003", parentLockerID: "50003")
        let students = [50001, 50002, 50003].compactMap { id in
            ParentLockerRosterStudent(json: .object([
                "student_id": .int(id), "first_name": .string("Child"), "last_name": .string("\(id)"),
                "attendance": .object([
                    "attendance_code_id": .string("703"), "attendance_code": .object(["id": .string("703")]),
                    "comment": .string("Sick"), "confirmed": .bool(true)
                ])
            ]))
        }
        let roster = ParentLockerRoster(course: course, students: students, marks: FakeParentLocker.marks)
        let family = Self.absent(.family)
        let plan = Planner.plan(
            children: [ours, theirs, otherClass],
            marks: [ours.id: family, theirs.id: family, otherClass.id: family],
            rosters: [roster], day: Device.morning,
            ownNotes: [ours.id: [course.courseID: ["Sick"]], otherClass.id: [5102: ["Sick"]]]
        )
        let sent = Dictionary(uniqueKeysWithValues: (plan.batches.first?.entries ?? []).map { ($0.childID, $0) })
        #expect(sent[ours.id]?.comment == "Family")
        #expect(sent[theirs.id] == nil, "the parent's Sick stays, on the mark it already holds")
        #expect(sent[otherClass.id] == nil, "written in another class's box")
        #expect(plan.upToDate == [theirs.id, otherClass.id])
    }

    @Test("Close Arrival's absence leaves a Sick the office typed (W3)")
    func officesSickStays() async {
        site.kids[4].comment = "Sick"
        let device = Fix1105CDevice(site: site, clock: clock)
        device.sync.closeArrivalSend(on: Device.morning, after: 6)
        clock.advance(by: Marks.sendsAfter)
        await device.sync.runDue()
        #expect(site.mark(41004) == "703")
        #expect(site.kids[4].comment == "Sick")
    }

    @Test("A reason the office typed isn't replaced by the guide's (W3)")
    func officesReasonNotReplaced() async {
        site.kids[3].comment = "Family"
        let device = Fix1105CDevice(site: site, clock: clock, sent: true)
        device.marks([Device.odile: Self.absent(.sick)])
        clock.advance(by: ParentLockerSync.localQuiet)
        await device.sync.runDue()
        #expect(site.mark(41002) == "703")
        #expect(site.kids[3].comment == "Family")
    }

    @Test("This device's own reason is replaced, then cleared, across a relaunch too (W3)")
    func ownReasonAcrossLaunches() async {
        let unsent = ParentLockerMemoryUnsentStore()
        let device = Fix1105CDevice(site: site, clock: clock, unsent: unsent, sent: true)
        device.marks([Device.bea: Self.absent(.sick)])
        clock.advance(by: ParentLockerSync.localQuiet)
        await device.sync.runDue()
        #expect(site.kids[4].comment == "Sick")
        device.marks([Device.bea: Self.absent(.family)])
        clock.advance(by: ParentLockerSync.localQuiet)
        await device.sync.runDue()
        #expect(site.kids[4].comment == "Family")
        device.sync.stop()

        let marks = device.store.state.marks
        let again = Fix1105CDevice(site: site, clock: clock, unsent: unsent, sent: true, marks: marks)
        again.marks([Device.bea: Device.mark(.tardy)])
        clock.advance(by: ParentLockerSync.localQuiet)
        await again.sync.runDue()
        #expect(site.mark(41004) == "702")
        #expect(site.kids[4].comment.isEmpty, "its own word goes, though written before the relaunch")
    }

    // MARK: - W4 The left-early time

    @Test("The app's own left-early line: AM/PM in any case, a.m./p.m., or a two-digit 24-hour time (W4)")
    func leftEarlyTimes() {
        let ours = [
            "1:30 PM", "1:30 pm", "1:30 Pm", "1:30 p.m.", "1:30 P.M.", "11:05 AM", "11:05 a.m.", "12:00 PM",
            "01:30 PM", "1:30\u{202F}PM", "1:30\u{202F}pm", "13:30", "09:15", "00:05", "23:59"
        ]
        for time in ours {
            #expect(Planner.isAppNote("Left early at " + time), "\(time)")
        }
        let theirs = [
            "2:15", "9:15", "1:30PM", "13:30 PM", "0:30 AM", "1:3 PM", "24:00", "1:30 PM.", "1:30  PM",
            "1:30 PM with Dad", "13:30:00", "1:30 PMs", "1:30 a.m"
        ]
        for time in theirs {
            #expect(!Planner.isAppNote("Left early at " + time), "\(time)")
        }
    }
}
