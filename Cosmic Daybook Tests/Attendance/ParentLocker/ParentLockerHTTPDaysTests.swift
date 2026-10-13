import Foundation
import Testing
@testable import CosmicDaybook

// Another day's class list, and a report id sent back as it came (report
// "ParentLocker bug check 2026-10-13", A1 and A4). In the requests suite, so
// they take their turn with its other tests on the one stub network.
extension ParentLockerHTTPTests {

    private nonisolated static let daysHost = "school.parentlocker.test"

    private func daysTransport() -> ParentLockerHTTP {
        ParentLockerHTTP(
            site: "https://\(Self.daysHost)/sis/",
            cookies: [ParentLockerCookie(name: "PHPSESSID", value: "session-1", domain: Self.daysHost)],
            configuration: ParentLockerStubProtocol.configuration()
        )
    }

    private nonisolated static func reply(_ body: Data) -> ParentLockerStubProtocol.Reply {
        .page(status: 200, headers: [:], body: body)
    }

    @Test("Another day's class list is that day's page, which carries its own report ids")
    func coursesForAnotherDay() async throws {
        let html = try ParentLockerFixtures.data("page.html")
        ParentLockerStubProtocol.reset { _ in Self.reply(html) }
        let friday = try CoreDataTestHelpers.day("2026-10-09")
        _ = try await daysTransport().courses(on: friday)
        _ = try await daysTransport().courses(on: nil)

        let asked = ParentLockerStubProtocol.seen.map(\.url.absoluteString)
        #expect(asked == [
            "https://\(Self.daysHost)/sis/newattendance.php?date=2026-10-9",
            "https://\(Self.daysHost)/sis/newattendance.php"
        ])
    }

    @Test("A save sends the report id back exactly as the page gave it, and refuses a missing one")
    func reportIDSentAsGiven() async throws {
        let page = """
            var courses = [{"course_id":5101,"course_name":"Girls Middle School","period":1,\
            "attendance_report_id":5842820,"attendance_report_status":"not_submitted",\
            "isDailyAttendance":true,"hasAttendance":true},{"course_id":5102,\
            "course_name":"Upper Elementary Girls","period":1,"attendance_report_id":null,\
            "attendance_report_status":"","isDailyAttendance":true,"hasAttendance":true}];
            """
        let courses = try #require(ParentLockerCourse.courses(inPage: page))
        let saved = try ParentLockerFixtures.data("save-reply.json")
        ParentLockerStubProtocol.reset { _ in Self.reply(saved) }

        let numbered = ParentLockerPlanner.Batch(
            course: courses[0], attendanceReportID: courses[0].attendanceReportID, date: "2026-10-12", entries: []
        )
        _ = try await daysTransport().save(batch: numbered)
        let body = try JSONDecoder().decode(
            ParentLockerJSON.self, from: try #require(ParentLockerStubProtocol.seen.first?.body)
        )
        #expect(body["attendance_report_id"] == .int(5_842_820))

        ParentLockerStubProtocol.reset { _ in Self.reply(saved) }
        let missing = ParentLockerPlanner.Batch(
            course: courses[1], attendanceReportID: courses[1].attendanceReportID, date: "2026-10-12", entries: []
        )
        await #expect(throws: ParentLockerError.pageChanged) { try await daysTransport().save(batch: missing) }
        #expect(ParentLockerStubProtocol.seen.isEmpty, "nothing was sent")
    }
}
