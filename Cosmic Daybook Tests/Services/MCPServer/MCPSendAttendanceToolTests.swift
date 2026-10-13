import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// `send_attendance_to_school` (plan "ParentLocker attendance", Phase 3): a
/// preview reads ParentLocker and writes nothing anywhere, a send changes the
/// marks that differ and records the day, a Debug build only previews, and
/// the reply never carries the sign-in. Over the ParentLocker sync's fake
/// site, clock and keychain (`ParentLockerSyncFakes`).
@Suite("MCP send attendance to school")
@MainActor
struct MCPSendAttendanceToolTests {

    typealias Device = ParentLockerTestDevice

    let site = FakeParentLocker()
    let clock = FakeParentLockerClock(Device.morning)

    /// The class as marked in the notebook; ParentLocker holds nothing yet.
    private static let marks: [UUID: ParentLockerPlanner.DayMark] = [
        Device.wren: Device.mark(.present), Device.june: Device.mark(.absent, reason: "sick"),
        Device.marisol: Device.mark(.tardy), Device.odile: Device.mark(.present),
        Device.bea: Device.mark(.present)
    ]

    private func device(policy: ParentLockerSavePolicy = .live) -> Device {
        Device(site: site, clock: clock, policy: policy, marks: Self.marks)
    }

    /// Calls the tool as the server does, with an outcome bound, and returns
    /// the reply and whether the call said it wrote nothing.
    private func call(
        _ arguments: [String: JSONValue], sync: ParentLockerSync?
    ) async throws -> (reply: String, wroteNothing: Bool) {
        let tool = MCPNotebookTools.sendAttendanceToSchoolTool(parentLocker: { sync })
        let outcome = MCPCallOutcome()
        let reply = try await MCPCallOutcome.$current.withValue(outcome) { try await tool.handler(arguments) }
        return (reply, outcome.wroteNothing)
    }

    /// The message of the tool error a call throws.
    private func failure(_ arguments: [String: JSONValue], sync: ParentLockerSync?) async -> String? {
        do {
            _ = try await call(arguments, sync: sync)
            return nil
        } catch let error as MCPToolError {
            return error.message
        } catch {
            return "\(error)"
        }
    }

    @Test("It is the one tool that reaches outside the notebook, and it writes")
    func annotations() {
        let annotations = MCPNotebookTools.sendAttendanceToSchoolTool(parentLocker: { nil }).annotations
        #expect(annotations.openWorldHint)
        #expect(!annotations.readOnlyHint)
        #expect(!annotations.destructiveHint)
    }

    @Test("A preview reads ParentLocker and says what would go, saving and recording nothing")
    func previewWritesNothing() async throws {
        let device = device()
        let (reply, wroteNothing) = try await call(["date": "2026-10-12", "preview": true], sync: device.sync)

        #expect(wroteNothing)
        #expect(site.saves.isEmpty)
        #expect(device.store.recordedSends.isEmpty)
        #expect(device.store.writtenMatches.isEmpty)
        #expect(reply.contains("nothing was sent"))
        #expect(reply.contains("Girls Middle School: 3 to send"))
        #expect(reply.contains("Marisol P: Late"))
        #expect(reply.contains("Juniper") == false, "children are named as the class reads them")
    }

    @Test("A send changes the marks that differ, records the day once, and keeps the sign-in out of the reply")
    func sendRecordsTheDay() async throws {
        let device = device()
        let (reply, wroteNothing) = try await call(["date": "2026-10-12"], sync: device.sync)

        #expect(!wroteNothing)
        #expect(Set(site.saves.map(\.course.courseID)) == [5101, 5102])
        #expect(site.mark(40002) == "703")
        #expect(site.mark(40003) == "702")
        #expect(device.store.recordedSends.count == 1)
        #expect(reply.hasPrefix("Sent to ParentLocker for"))
        #expect(reply.contains("5 children changed"))
        for secret in ["made-up-password", "guide@school.test", "PHPSESSID", FakeParentLocker.host] {
            #expect(!reply.contains(secret), "the reply never carries \(secret)")
        }

        // Again: nothing differs now, so nothing is saved.
        site.saves = []
        let (again, _) = try await call(["date": "2026-10-12"], sync: device.sync)
        #expect(site.saves.isEmpty)
        #expect(again.contains("0 children changed"))
    }

    @Test("A Debug build only previews, and the call says so and writes nothing")
    func previewOnlyBuild() async throws {
        let device = device(policy: .previewOnly)
        let (reply, wroteNothing) = try await call(["date": "2026-10-12"], sync: device.sync)

        #expect(wroteNothing)
        #expect(site.saves.isEmpty)
        #expect(device.store.recordedSends.isEmpty)
        #expect(reply.contains("only previews"))
    }

    @Test("With the email picked, or no sync running, it refuses in plain words")
    func refusals() async {
        let device = device()
        device.store.state.method = .email
        let email = await failure(["date": "2026-10-12"], sync: device.sync)
        #expect(email == "Attendance goes by email. Pick ParentLocker in Settings to send it there.")
        #expect(site.requests.isEmpty)
        #expect(device.store.recordedSends.isEmpty)

        let notRunning = await failure(["date": "2026-10-12"], sync: nil)
        #expect(notRunning?.contains("isn't running yet") == true)
    }

    // MARK: - attendance_for_day

    @Test("attendance_for_day says whether the day went to ParentLocker, and the email line stays for the email")
    func attendanceForDayReportsParentLocker() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let tools = MCPNotebookTools.makeTools(context: { context })
        let read = try #require(tools.first { $0.name == "attendance_for_day" })
        CoreDataTestHelpers.seedClassroomMembership(in: context, role: .leadGuide)
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Nina", lastName: "Barr")
        let settings = AttendanceEmailLog.Settings(
            isEnabled: true, toAddresses: "office@school.test", nameOrder: .firstLast, groupByLevel: false,
            sendMethod: .parentLocker
        )
        #expect(AttendanceEmailLog.saveSettings(settings, role: .leadGuide, in: context))
        #expect(CoreDataTestHelpers.save(context))
        let day = try #require(AppCalendar.shared.date(from: DateComponents(year: 2026, month: 9, day: 14)))

        let before = try await read.handler(["date": "2026-09-14"])
        #expect(before.contains("  ParentLocker: not sent yet"))
        #expect(!before.contains("Front desk email"))

        let sentAt = day.addingTimeInterval(8 * 3_600 + 47 * 60)
        AttendanceEmailLog.recordSend(on: day, role: .leadGuide, channel: .parentLocker, now: sentAt, in: context)
        #expect(CoreDataTestHelpers.save(context))
        let after = try await read.handler(["date": "2026-09-14"])
        #expect(after.contains("  ParentLocker: Sent to ParentLocker"))
        #expect(after.contains("by the guide"))

        var email = settings
        email.sendMethod = .email
        #expect(AttendanceEmailLog.saveSettings(email, role: .leadGuide, in: context))
        #expect(CoreDataTestHelpers.save(context))
        let byEmail = try await read.handler(["date": "2026-09-14"])
        #expect(byEmail.contains("  Front desk email: Sent to ParentLocker"), "the day's send, worded by how it went")
        #expect(!byEmail.contains("  ParentLocker:"))
    }
}
