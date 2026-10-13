import Foundation
import Testing
@testable import CosmicDaybook

/// Which day a send is for, and its record, as the 2026-10-13 bug check found
/// them (report "ParentLocker bug check 2026-10-13", C2, C3, D3, A1, A3): a
/// day ahead refused however it's asked for, a past day saved under its own
/// report and kept off today's line, the day's send recorded once, and a
/// sign-in closed partway keeping nothing. Over the fake site, clock and keychain.
@Suite("ParentLocker sending days")
@MainActor
struct ParentLockerSendingDaysTests {

    typealias Device = ParentLockerTestDevice

    let site = FakeParentLocker()
    let clock = FakeParentLockerClock(Device.morning)

    /// The class marked, Bea absent by Close Arrival; ParentLocker holds nothing yet.
    private static let closed: [UUID: ParentLockerPlanner.DayMark] = [
        Device.wren: Device.mark(.present), Device.june: Device.mark(.present),
        Device.marisol: Device.mark(.tardy), Device.odile: Device.mark(.present),
        Device.bea: Device.mark(.absent, reason: AttendanceDeduplication.automaticAbsenceRaw)
    ]

    // MARK: - D3 The day's send, once

    @Test("A day already recorded as sent isn't recorded again, so a day sent on time stays on time")
    func sendRecordedOnce() async {
        let device = Device(site: site, clock: clock, marks: Self.closed)
        await device.sync.sendNow(day: Device.morning)
        #expect(device.store.recordedSends.count == 1)

        // Send Again, MCP, and a Close Arrival & Send: none records a second.
        device.marks([Device.odile: Device.mark(.tardy)])
        await device.sync.sendNow(day: Device.morning)
        _ = await device.sync.send(day: Device.morning, preview: false)
        device.sync.closeArrivalSend(on: Device.morning, after: 6)
        clock.advance(by: 6)
        await device.sync.runDue()
        #expect(site.mark(41002) == "702")
        #expect(device.store.recordedSends.count == 1)
    }

    // MARK: - C2, C3, A1 Other days

    @Test("A day that hasn't come yet is refused, however it's asked for")
    func futureDayRefused() async {
        let device = Device(site: site, clock: clock, marks: Self.closed)
        let tomorrow = Device.morning.addingTimeInterval(86_400)
        let before = device.sync.status
        let status = await device.sync.sendNow(day: tomorrow)
        #expect(status.state != .upToDate)
        for preview in [false, true] {
            switch await device.sync.send(day: tomorrow, preview: preview) {
            case .success: Issue.record("tomorrow went (preview: \(preview))")
            case .failure(let failure): #expect(failure.message.contains("hasn't come yet"))
            }
        }
        #expect(site.requests.isEmpty)
        #expect(device.store.recordedSends.isEmpty)
        #expect(device.sync.status == before)
    }

    @Test("MCP's send for tomorrow is refused in plain words, and nothing is sent or recorded")
    func mcpTomorrowRefused() async {
        let device = Device(site: site, clock: clock, marks: Self.closed)
        let tool = MCPNotebookTools.sendAttendanceToSchoolTool(parentLocker: { device.sync })
        do {
            _ = try await MCPCallOutcome.$current.withValue(MCPCallOutcome()) {
                try await tool.handler(["date": "2026-10-13"])
            }
            Issue.record("tomorrow went to ParentLocker")
        } catch let error as MCPToolError {
            #expect(error.message.contains("hasn't come yet"))
        } catch {
            Issue.record("unexpected \(error)")
        }
        #expect(site.requests.isEmpty)
        #expect(device.store.recordedSends.isEmpty)
    }

    @Test("Send Now for a past day saves under that day's own report, and leaves today's line alone")
    func pastDaySend() async {
        let device = Device(site: site, clock: clock, marks: Self.closed)
        let friday = Device.morning.addingTimeInterval(-3 * 86_400)
        let before = device.sync.status
        let status = await device.sync.sendNow(day: friday)
        #expect(status.state == .upToDate, "the toast says how Friday went")
        #expect(site.requests.first == "courses 2026-10-9")
        #expect(Set(site.saves.map(\.attendanceReportID)) == ["770001", "770002"])
        #expect(site.saves.allSatisfy { $0.date == "2026-10-9" })
        #expect(device.store.recordedSends.count == 1)
        #expect(device.sync.status == before, "today's line says nothing of Friday")
    }

    // MARK: - A3 Cancelling the sign-in

    @Test("Closing the sign-in while it checks the class list keeps nothing")
    func cancelledSignInKeepsNothing() async throws {
        let secrets = FakeParentLockerSecrets(password: nil, cookie: nil)
        let device = Device(site: site, clock: clock, secrets: secrets)
        let credential = ParentLockerKeychain.Credential(email: "guide@school.test", password: site.password)
        let cookies = [ParentLockerCookie(name: "PHPSESSID", value: "good", domain: FakeParentLocker.host)]
        let attempt = Task {
            try await device.sync.completeSignIn(credential, cookies: cookies, site: FakeParentLocker.host)
        }
        attempt.cancel()
        await #expect(throws: ParentLockerSignInError.cancelled) { try await attempt.value }
        #expect(site.requests == ["courses"], "the final check ran")
        #expect(try secrets.credential(site: FakeParentLocker.host) == nil)
        #expect(secrets.savedCookies.isEmpty)
        #expect(!device.sync.isSignedIn)
    }
}
