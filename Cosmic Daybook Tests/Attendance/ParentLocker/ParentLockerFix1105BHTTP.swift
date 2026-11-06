import Foundation
import Testing
@testable import CosmicDaybook

// The request side of the 2026-11-05 fixes (fix agent B): temporary server
// trouble reads as "try again later" (#22), the session's timeouts (#7), and a
// period that isn't a number sent back as it came. In the requests suite, so
// they take their turn with its other tests on the one stub network.
extension ParentLockerHTTPTests {

    private nonisolated static let fixHost = "school.parentlocker.test"

    private func fixTransport() -> ParentLockerHTTP {
        ParentLockerHTTP(
            site: "https://\(Self.fixHost)/sis/",
            cookies: [ParentLockerCookie(name: "PHPSESSID", value: "session-1", domain: Self.fixHost)],
            configuration: ParentLockerStubProtocol.configuration()
        )
    }

    private nonisolated static func fixReply(_ body: Data, status: Int = 200) -> ParentLockerStubProtocol.Reply {
        .page(status: status, headers: [:], body: body)
    }

    private func rosterError(status: Int = 200, body: String) async -> ParentLockerError? {
        ParentLockerStubProtocol.reset { _ in Self.fixReply(Data(body.utf8), status: status) }
        do {
            _ = try await fixTransport().roster(course: ParentLockerFixtures.middleSchool, date: Date())
            return nil
        } catch {
            return error as? ParentLockerError
        }
    }

    @Test("Temporary server trouble reads as unreachable, so it's retried: 408, 429, 5xx, a maintenance page")
    func temporaryTroubleIsUnreachable() async {
        for status in [408, 429, 500, 502, 503, 504] {
            #expect(await rosterError(status: status, body: "") == .unreachable, "status \(status)")
        }
        let maintenance = "<html><body><h1>Down for maintenance</h1><p>Back soon.</p></body></html>"
        #expect(await rosterError(body: maintenance) == .unreachable)
        #expect(await rosterError(body: "") == .unreachable)
    }

    @Test("A 404, a JSON reply of another shape, and the sign-in page still read as they did")
    func realChangesStay() async throws {
        #expect(await rosterError(status: 404, body: "") == .pageChanged)
        #expect(await rosterError(body: "[1, 2, 3]") == .pageChanged)
        #expect(await rosterError(body: #"{"something_else": true}"#) == .pageChanged)
        #expect(await rosterError(status: 401, body: "") == .signedOut)
        #expect(await rosterError(body: try ParentLockerFixtures.text("signin.html")) == .signedOut)
        #expect(ParentLockerHTTP.error(forStatus: 404) == .pageChanged)
        #expect(ParentLockerHTTP.error(forStatus: 400) == .pageChanged)
        #expect(ParentLockerHTTP.error(forStatus: 429) == .unreachable)
        #expect(ParentLockerHTTP.error(forStatus: 408) == .unreachable)
    }

    @Test("The session gives up on a stalled request after 20 s and on any request after 45 s")
    func timeouts() {
        let configuration = fixTransport().session.configuration
        #expect(configuration.timeoutIntervalForRequest == 20)
        #expect(configuration.timeoutIntervalForResource == 45)
        let shared = ParentLockerHTTP.makeSession().configuration
        #expect(shared.timeoutIntervalForRequest == 20)
        #expect(shared.timeoutIntervalForResource == 45)
    }

    @Test("A period that isn't a number goes back in the roster request exactly as the page gave it")
    func textPeriodSentAsGiven() async throws {
        let html = """
            <script>
            var courses = [{"course_id": 6001, "course_name": "Art", "period": "A", "attendance_report_id": "9001", \
            "isDailyAttendance": 1, "hasAttendance": 1}];
            </script>
            """
        let rosterReply = Data(#"{"students": [], "attendance_settings": [], "is_today": true}"#.utf8)
        ParentLockerStubProtocol.reset { request in
            Self.fixReply(request.httpMethod == "POST" ? rosterReply : Data(html.utf8))
        }
        let course = try #require(try await fixTransport().courses(on: nil).first)
        _ = try await fixTransport().roster(course: course, date: try CoreDataTestHelpers.day("2026-10-12"))

        let post = try #require(ParentLockerStubProtocol.seen.last { $0.method == "POST" })
        let body = try JSONDecoder().decode(ParentLockerJSON.self, from: try #require(post.body))
        #expect(body["period"] == .string("A"))
        #expect(body["course_id"] == .int(6001))
    }
}
