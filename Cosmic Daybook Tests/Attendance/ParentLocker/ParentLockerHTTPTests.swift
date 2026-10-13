import Foundation
import Synchronization
import Testing
@testable import CosmicDaybook

/// ParentLocker's three requests over a stubbed network
/// (`ParentLockerStubProtocol`), with the recorded replies: the course list
/// read from the page, "signed out" told apart from "the page changed", no
/// redirect followed off the site, cookies carried by hand and never into
/// the shared cookie storage, and every `Set-Cookie` taken back.
@Suite("ParentLocker requests", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct ParentLockerHTTPTests {

    private typealias Stub = ParentLockerStubProtocol
    private nonisolated static let host = "school.parentlocker.test"

    private static let signedIn = [
        ParentLockerCookie(name: "PHPSESSID", value: "session-1", domain: host),
        ParentLockerCookie(name: "plRemember", value: "remember-1", domain: ".parentlocker.test", path: "/"),
        ParentLockerCookie(name: "elsewhere", value: "x", domain: "other.example")
    ]

    private nonisolated static func page(
        _ data: Data, status: Int = 200, headers: [String: String] = [:]
    ) -> Stub.Reply {
        .page(status: status, headers: headers, body: data)
    }

    private func transport(
        cookies: [ParentLockerCookie] = signedIn,
        changed: (@Sendable ([ParentLockerCookie]) -> Void)? = nil
    ) -> ParentLockerHTTP {
        ParentLockerHTTP(
            site: "https://\(Self.host)/sis/", cookies: cookies,
            configuration: Stub.configuration(), cookiesChanged: changed
        )
    }

    // MARK: - Courses

    @Test("The course list is read from the page, with the cookies sent by hand")
    func coursesFromPage() async throws {
        let html = try ParentLockerFixtures.data("page.html")
        Stub.reset { _ in Self.page(html) }
        let courses = try await transport().courses()

        #expect(courses.map(\.courseID) == [5101, 5102, 5103])
        #expect(courses.map(\.name) == ["Girls Middle School", "Upper Elementary Girls", "Study Hall; Room [4]"])
        #expect(courses.map(\.attendanceReportID) == ["880001", "880002", "880003"])
        #expect(courses.map(\.period) == [1, 1, 3])
        #expect(courses[1].reportStatus == "submitted" && courses[1].isDailyAttendance)
        #expect(!courses[2].isDailyAttendance)

        let request = try #require(Stub.seen.first)
        #expect(Stub.seen.count == 1)
        #expect(request.url.absoluteString == "https://\(Self.host)/sis/newattendance.php")
        #expect(request.method == "GET")
        // Its own cookie and the domain's, never another site's.
        let cookie = try #require(request.headers["Cookie"])
        #expect(Set(cookie.components(separatedBy: "; ")) == ["PHPSESSID=session-1", "plRemember=remember-1"])
    }

    @Test("The sign-in page where the attendance page should be reads as signed out")
    func signedOutPage() async throws {
        let html = try ParentLockerFixtures.data("signin.html")
        Stub.reset { _ in Self.page(html) }
        await #expect(throws: ParentLockerError.signedOut) { try await transport().courses() }
        await #expect(throws: ParentLockerError.signedOut) {
            try await transport().roster(course: ParentLockerFixtures.middleSchool, date: Date())
        }
    }

    @Test("A redirect on the site where the page should be reads as signed out")
    func sameSiteRedirect() async throws {
        let login = try #require(URL(string: "https://\(Self.host)/login.php?return_to=sis"))
        Stub.reset { request in
            request.url?.path == "/login.php" ? Self.page(Data()) : .redirect(to: login, headers: [:])
        }
        await #expect(throws: ParentLockerError.signedOut) { try await transport().courses() }
        #expect(!Stub.seen.contains { $0.url.path == "/login.php" })
    }

    @Test("A page that is neither the attendance page nor the sign-in reads as changed")
    func pageChanged() async throws {
        let html = try ParentLockerFixtures.data("changed.html")
        Stub.reset { _ in Self.page(html) }
        await #expect(throws: ParentLockerError.pageChanged) { try await transport().courses() }
        Stub.reset { _ in Self.page(Data(), status: 404) }
        await #expect(throws: ParentLockerError.pageChanged) { try await transport().courses() }
        Stub.reset { _ in Self.page(Data(), status: 503) }
        await #expect(throws: ParentLockerError.unreachable) { try await transport().courses() }
    }

    // MARK: - Redirects and cookies

    @Test("A redirect to another host is refused: nothing, cookies included, goes there")
    func offSiteRedirectRefused() async throws {
        let evil = try #require(URL(string: "https://collector.example/steal"))
        Stub.reset { request in
            request.url?.host == Self.host ? .redirect(to: evil, headers: [:]) : Self.page(Data("gotcha".utf8))
        }
        await #expect(throws: ParentLockerError.redirectedOffSite(host: "collector.example")) {
            try await transport().courses()
        }
        #expect(Stub.seen.allSatisfy { $0.url.host == Self.host })
    }

    @Test("Nothing lands in the shared cookie storage")
    func sharedStorageUntouched() async throws {
        let url = try #require(URL(string: "https://\(Self.host)/sis/newattendance.php"))
        let before = HTTPCookieStorage.shared.cookies(for: url) ?? []
        let html = try ParentLockerFixtures.data("page.html")
        Stub.reset { _ in
            Self.page(html, headers: ["Set-Cookie": "PHPSESSID=session-2; Path=/; Secure; HttpOnly"])
        }
        let transport = transport()
        _ = try await transport.courses()
        #expect((HTTPCookieStorage.shared.cookies(for: url) ?? []).count == before.count)
        #expect(!(HTTPCookieStorage.shared.cookies ?? []).contains { $0.value == "session-2" })
        #expect(transport.cookies.contains { $0.value == "session-2" })
    }

    @Test("Cookies the site sets replace the ones kept, and the change is passed on")
    func cookiesUpdated() async throws {
        let html = try ParentLockerFixtures.data("page.html")
        Stub.reset { _ in
            Self.page(html, headers: ["Set-Cookie": "PHPSESSID=session-2; Path=/; Secure; HttpOnly"])
        }
        let heard = Mutex<[[ParentLockerCookie]]>([])
        let transport = transport { jar in heard.withLock { $0.append(jar) } }
        _ = try await transport.courses()

        let session = transport.cookies.filter { $0.name == "PHPSESSID" }
        #expect(session.map(\.value) == ["session-2"])
        #expect(transport.cookies.contains { $0.name == "plRemember" })
        #expect(!transport.cookies.contains { $0.domain == "other.example" })
        #expect(heard.withLock { $0 }.last == transport.cookies)

        // The same cookie again changes nothing, so nothing is passed on.
        _ = try await transport.courses()
        #expect(heard.withLock { $0 }.count == 1)

        // An expired one is the site deleting it.
        Stub.reset { _ in
            Self.page(html, headers: ["Set-Cookie": "plRemember=gone; Domain=.parentlocker.test; Path=/; " +
                "Expires=Thu, 01 Jan 1970 00:00:00 GMT"])
        }
        _ = try await transport.courses()
        #expect(!transport.cookies.contains { $0.name == "plRemember" })
        #expect(heard.withLock { $0 }.count == 2)
    }

    @Test("A cookie set on a redirect is kept too")
    func cookieOnRedirect() async throws {
        let login = try #require(URL(string: "https://\(Self.host)/login.php"))
        Stub.reset { _ in .redirect(to: login, headers: ["Set-Cookie": "PHPSESSID=expired-1; Path=/"]) }
        let transport = transport()
        await #expect(throws: ParentLockerError.signedOut) { try await transport.courses() }
        #expect(transport.cookies.first { $0.name == "PHPSESSID" }?.value == "expired-1")
    }

    // MARK: - Roster and save

    @Test("A roster is asked for as the page asks, and read with its marks")
    func rosterRequest() async throws {
        let reply = try ParentLockerFixtures.data("roster-middle.json")
        Stub.reset { _ in Self.page(reply) }
        let day = try CoreDataTestHelpers.day("2026-10-12")
        let roster = try await transport().roster(course: ParentLockerFixtures.middleSchool, date: day)
        #expect(roster.students.count == 7)
        #expect(roster.marks.count == 5)
        #expect(roster.isToday)

        let request = try #require(Stub.seen.first)
        #expect(request.method == "POST")
        #expect(request.headers["Content-Type"]?.hasPrefix("application/json") == true)
        let body = try JSONDecoder().decode(ParentLockerJSON.self, from: try #require(request.body))
        #expect(body == .object([
            "action": .string("course_roster"), "course_id": .int(5101),
            "period": .int(1), "date": .string("2026-10-12")
        ]))
    }

    @Test("A save sends the planned objects and reads the conflicts")
    func saveRequest() async throws {
        let reply = try ParentLockerFixtures.data("save-reply.json")
        Stub.reset { _ in Self.page(reply) }
        let roster = try #require(try ParentLockerFixtures.rosters().first)
        let wren = ParentLockerPlanner.Child(id: UUID(), firstName: "Wren", lastName: "Halloway")
        let plan = ParentLockerPlanner.plan(
            children: [wren], marks: [wren.id: .init(statusRaw: "present")], rosters: [roster],
            day: try CoreDataTestHelpers.day("2026-10-12")
        )
        let batch = try #require(plan.batches.first)
        let saved = try await transport().save(batch: batch)

        #expect(saved.conflicts.count == 2)
        #expect(saved.conflicts.map(\.alreadyEqual) == [false, true])
        #expect(saved.conflicts.first?.studentID == "40001")
        let body = try JSONDecoder().decode(ParentLockerJSON.self, from: try #require(Stub.seen.first?.body))
        #expect(body["action"] == .string("save"))
        #expect(body["attendance_report_id"] == .string("880001"))
        #expect(body["date"] == .string("2026-10-12"))
        #expect(body["students"] == .array(batch.students))
    }

    @Test("A save the site refuses throws with its message kept for the details")
    func saveRefused() async throws {
        let reply = try ParentLockerFixtures.data("save-refused.json")
        Stub.reset { _ in Self.page(reply) }
        let batch = ParentLockerPlanner.Batch(
            course: ParentLockerFixtures.middleSchool, attendanceReportID: "880001", date: "2026-10-12", entries: []
        )
        await #expect(throws: ParentLockerError.refused(message: "Attendance for this date is closed.")) {
            try await transport().save(batch: batch)
        }
        #expect(ParentLockerError.refused(message: "x").errorDescription?.contains("x") == false)
    }
}
