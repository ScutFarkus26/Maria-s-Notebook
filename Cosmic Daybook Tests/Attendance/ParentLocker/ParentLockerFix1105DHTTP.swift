import Foundation
import Testing
@testable import CosmicDaybook

// The review of the 2026-11-05 fixes (W5): a 200 page on the first load that
// isn't the attendance page or the sign-in. One with no script at all can't
// be ParentLocker's attendance page, which takes attendance in script, so
// it's something in front of the site (a maintenance page, an empty reply):
// "try again later". One with script but no class list stays "page changed".
// In the requests suite, so they take their turn on the one stub network.
extension ParentLockerHTTPTests {

    private nonisolated static let fix1105DHost = "school.parentlocker.test"

    private func pageError(_ body: String) async -> ParentLockerError? {
        ParentLockerStubProtocol.reset { _ in .page(status: 200, headers: [:], body: Data(body.utf8)) }
        let transport = ParentLockerHTTP(
            site: "https://\(Self.fix1105DHost)/sis/",
            cookies: [ParentLockerCookie(name: "PHPSESSID", value: "session-1", domain: Self.fix1105DHost)],
            configuration: ParentLockerStubProtocol.configuration()
        )
        do {
            _ = try await transport.courses(on: nil)
            return nil
        } catch {
            return error as? ParentLockerError
        }
    }

    @Test("W5: a maintenance page or an empty reply where the attendance page should be is tried again later")
    func maintenancePageIsUnreachable() async {
        let maintenance = """
            <!DOCTYPE html><html><head><title>Down for maintenance</title>
            <style>body { font-family: sans-serif; }</style></head>
            <body><h1>We'll be back soon</h1><p>The site is down for maintenance.</p></body></html>
            """
        #expect(await pageError(maintenance) == .unreachable)
        #expect(await pageError("") == .unreachable)
        #expect(await pageError("<html><body>Service unavailable</body></html>") == .unreachable)
        // A <noscript> note alone isn't script.
        #expect(await pageError("<html><body><noscript>Turn on JavaScript</noscript></body></html>") == .unreachable)
    }

    @Test("W5: a page with script but no class list still reads as changed, and the sign-in as signed out")
    func scriptedPageStaysChanged() async throws {
        #expect(await pageError(try ParentLockerFixtures.text("changed.html")) == .pageChanged)
        let rewritten = """
            <!DOCTYPE html><html ng-app="attendanceApp"><head><title>Attendance</title>
            <SCRIPT type="text/javascript">var teacher = 9001;</SCRIPT></head>
            <body><div ng-controller="AttendanceCtrl">Take attendance</div></body></html>
            """
        #expect(await pageError(rewritten) == .pageChanged)
        #expect(await pageError(try ParentLockerFixtures.text("signin.html")) == .signedOut)
        #expect(await pageError(try ParentLockerFixtures.text("page.html")) == nil)
    }
}
