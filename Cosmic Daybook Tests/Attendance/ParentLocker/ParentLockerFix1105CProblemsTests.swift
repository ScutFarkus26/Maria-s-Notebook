import Foundation
import Testing
@testable import CosmicDaybook

/// The lines that stand on the ParentLocker line until a run shows them
/// fixed, as the review of the 2026-11-05 fixes found them (report
/// "ParentLocker in the Assistant bug hunt 2026-11-05", Review of the
/// fixes, E7, W2): a class ParentLocker keeps refusing to open, a mark the
/// school's page doesn't have, a row the office locked. Over the fake site,
/// clock and keychain.
@Suite("ParentLocker fixes 2026-11-05 C: lines that stand")
@MainActor
struct ParentLockerFix1105CProblemsTests {

    typealias Device = ParentLockerTestDevice
    typealias Marks = Fix1105AMarks

    let site = FakeParentLocker()
    let clock = FakeParentLockerClock(Device.morning)

    private var saves: [String] { site.requests.filter { $0.hasPrefix("save") } }

    private static let refusedLine = ParentLockerStatus.refusedClassLine("Upper Elementary Girls")

    // MARK: - E7 A class ParentLocker keeps refusing

    @Test("A class ParentLocker keeps refusing: once the other saved, the day is recorded and a line names it (E7)")
    func classKeepsRefusing() async {
        let device = Fix1105CDevice(site: site, clock: clock)
        device.wire.rosterFailures[5102] = Array(repeating: .refused(message: "error"), count: 20)
        device.sync.closeArrivalSend(on: Device.morning, after: 6)
        clock.advance(by: Marks.sendsAfter)
        await device.sync.runDue()
        #expect(saves == ["save 5101"])
        #expect(device.store.recordedSends.isEmpty, "a first refusal may pass")
        #expect(device.unsent.load()?.wholeClass == true)

        // The next change takes the class owed: refused again, the class stands.
        device.marks([Device.wren: Device.mark(.tardy)])
        clock.advance(by: ParentLockerSync.localQuiet)
        await device.sync.runDue()
        #expect(saves == ["save 5101", "save 5101"])
        #expect(device.store.recordedSends.count == 1)
        #expect(device.unsent.load()?.wholeClass != true, "nothing owed: it isn't run again at every change")
        #expect(device.sync.status.problems == [Self.refusedLine], "not \"Odile B and Bea M aren't matched\"")
        #expect(device.sync.status.message?.contains("Up to date") != true)
        #expect(device.sync.lastReport?.problems == [Self.refusedLine])

        // A later change goes by itself, and the line stands.
        device.marks([Device.june: Device.mark(.tardy)])
        clock.advance(by: ParentLockerSync.localQuiet)
        await device.sync.runDue()
        #expect(site.mark(40002) == "702")
        #expect(device.sync.status.problems == [Self.refusedLine])
        #expect(device.store.recordedSends.count == 1)
    }

    @Test("The class's line stands until a send of the whole class reads it again (E7, W2)")
    func refusedLineUntilTheClassGoes() async {
        let device = Fix1105CDevice(site: site, clock: clock)
        device.wire.rosterFailures[5102] = Array(repeating: .refused(message: "error"), count: 2)
        device.sync.closeArrivalSend(on: Device.morning, after: 6)
        clock.advance(by: Marks.sendsAfter)
        await device.sync.runDue()
        device.marks([Device.wren: Device.mark(.tardy)])
        clock.advance(by: ParentLockerSync.localQuiet)
        await device.sync.runDue()
        #expect(device.sync.status.problems == [Self.refusedLine])

        // ParentLocker opens the class again: Odile's change goes, but Bea's absence still hasn't.
        device.marks([Device.odile: Device.mark(.tardy)])
        clock.advance(by: ParentLockerSync.localQuiet)
        await device.sync.runDue()
        #expect(site.mark(41002) == "702")
        #expect(site.mark(41004) == nil)
        #expect(device.sync.status.problems == [Self.refusedLine])

        await device.sync.sendNow(day: Device.morning)
        #expect(site.mark(41004) == "703")
        #expect(device.sync.status.problems.isEmpty)
        #expect(device.sync.status.message == "Up to date in ParentLocker.")
    }

    // MARK: - W2 Lines a later run keeps

    @Test("A later run for one child keeps the class's other lines, until a run shows each fixed (W2)")
    func standingLinesStay() async throws {
        // The office locked Odile's row on Absent, and the school's page has no Late mark today.
        site.kids[3].markID = "703"
        site.kids[3].locked = true
        let device = Fix1105CDevice(site: site, clock: clock)
        device.wire.missingMarks = ["late"]
        device.sync.closeArrivalSend(on: Device.morning, after: 6)
        clock.advance(by: Marks.sendsAfter)
        await device.sync.runDue()
        let lines = device.sync.status.problems
        #expect(lines.count == 2)
        #expect(lines.contains { $0.hasPrefix("Late marks couldn't go for Marisol P") })
        #expect(lines.contains { $0.hasPrefix("The office already marked Odile B") })
        #expect(device.store.recordedSends.count == 1)

        // A change synced in for Wren goes live: the lines stand.
        device.imports([Device.wren: Device.mark(.absent, reason: AbsenceReason.sick.rawValue)])
        clock.advance(by: ParentLockerSync.importedWait)
        await device.sync.runDue()
        #expect(site.mark(40001) == "703")
        #expect(device.sync.status.problems == lines)
        #expect(device.sync.status.message?.contains("Up to date") != true)

        // The page has its Late mark back, and Marisol's next change goes: her line goes, Odile's stays.
        device.wire.missingMarks = []
        device.marks([Device.marisol: Device.mark(.tardy)])
        clock.advance(by: ParentLockerSync.localQuiet)
        await device.sync.runDue()
        #expect(site.mark(40003) == "702")
        #expect(device.sync.status.problems.count == 1)
        #expect(device.sync.status.problems.first?.hasPrefix("The office already marked Odile B") == true)
    }

    @Test("A child not matched yet stays on the line through other children's runs (W2)")
    func unmatchedLineStays() async {
        site.kids.removeAll { $0.studentID == 40002 }
        let device = Fix1105CDevice(site: site, clock: clock)
        device.sync.closeArrivalSend(on: Device.morning, after: 6)
        clock.advance(by: Marks.sendsAfter)
        await device.sync.runDue()
        let lines = device.sync.status.problems
        #expect(lines.count == 1)
        #expect(lines.first?.hasPrefix("Jun A isn't matched") == true)

        device.marks([Device.odile: Device.mark(.tardy)])
        clock.advance(by: ParentLockerSync.localQuiet)
        await device.sync.runDue()
        #expect(site.mark(41002) == "702")
        #expect(device.sync.status.problems == lines)
    }
}
