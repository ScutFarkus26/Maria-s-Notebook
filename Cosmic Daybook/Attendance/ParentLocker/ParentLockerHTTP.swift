import Foundation
import OSLog
import Synchronization

/// ParentLocker's three requests over `URLSession`, carrying the person's
/// sign-in cookies (plan "ParentLocker attendance", Privacy rules):
/// - The session is ephemeral and handles no cookies itself, so nothing
///   lands in the shared cookie storage or on disk; the cookies go on each
///   request by hand.
/// - No redirect is followed. One to another host is refused, so the cookies
///   never leave the site; one on the site where the page should be means the
///   site wants a sign-in.
/// - Every `Set-Cookie` the site sends back replaces the cookie it names, and
///   `cookiesChanged` hears about it so the Keychain copy follows.
/// - Logs carry status codes and counts only, never a reply's body or a cookie.
nonisolated final class ParentLockerHTTP: ParentLockerTransport {

    /// The site's host, cleaned (`AttendanceEmailLog.parentLockerHost`).
    let host: String
    private let session: URLSession
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let jar: Mutex<[ParentLockerCookie]>
    private let cookiesChanged: (@Sendable ([ParentLockerCookie]) -> Void)?

    private static let logger = Logger.attendance

    /// - Parameters:
    ///   - site: the site as Settings holds it.
    ///   - cookies: the saved sign-in cookies.
    ///   - configuration: the session's starting point; tests pass one with
    ///     a stub protocol. Its cookie, cache and credential handling is
    ///     turned off here whatever it says.
    ///   - cookiesChanged: told the whole jar whenever a reply changes it.
    init(
        site: String,
        cookies: [ParentLockerCookie],
        configuration: URLSessionConfiguration = .ephemeral,
        calendar: Calendar = AppCalendar.shared,
        now: @escaping @Sendable () -> Date = { Date() },
        cookiesChanged: (@Sendable ([ParentLockerCookie]) -> Void)? = nil
    ) {
        let host = AttendanceEmailLog.parentLockerHost(site)
        self.host = host
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
        self.calendar = calendar
        self.now = now
        jar = Mutex(ParentLockerCookie.merge(cookies, into: [], host: host, now: now()))
        self.cookiesChanged = cookiesChanged
    }

    deinit { session.invalidateAndCancel() }

    /// The cookies as they stand, for the Keychain.
    var cookies: [ParentLockerCookie] { jar.withLock { $0 } }

    /// The attendance page: `https://<host>/sis/newattendance.php`.
    var attendancePageURL: URL {
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = host
        parts.path = "/sis/newattendance.php"
        return parts.url ?? URL(fileURLWithPath: "/")
    }

    // MARK: - ParentLockerTransport

    func courses() async throws -> [ParentLockerCourse] {
        var request = URLRequest(url: attendancePageURL)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let data = try await send(request, label: "page")
        let html = Self.text(of: data)
        guard let courses = ParentLockerCourse.courses(inPage: html) else {
            throw Self.looksLikeSignIn(html) ? ParentLockerError.signedOut : ParentLockerError.pageChanged
        }
        Self.logger.info("ParentLocker: the page lists \(courses.count, privacy: .public) classes")
        return courses
    }

    func roster(course: ParentLockerCourse, date: Date) async throws -> ParentLockerRoster {
        let body: [String: ParentLockerJSON] = [
            "action": .string("course_roster"),
            "course_id": .int(course.courseID),
            "period": .int(course.period),
            "date": .string(ParentLockerPlanner.dateText(date, calendar: calendar))
        ]
        let reply = try await post(body, label: "roster")
        let roster = try ParentLockerRoster(reply: reply, course: course)
        Self.logger.info("ParentLocker: a roster of \(roster.students.count, privacy: .public) children")
        return roster
    }

    func save(batch: ParentLockerPlanner.Batch) async throws -> ParentLockerSaveReply {
        let body: [String: ParentLockerJSON] = [
            "action": .string("save"),
            "students": .array(batch.students),
            "attendance_report_id": .string(batch.attendanceReportID),
            "date": .string(batch.date)
        ]
        let reply = try ParentLockerSaveReply(reply: try await post(body, label: "save"))
        Self.logger.info("""
            ParentLocker: saved \(batch.entries.count, privacy: .public) children, \
            \(reply.conflicts.count, privacy: .public) conflicts
            """)
        return reply
    }

    // MARK: - Requests

    /// A JSON POST to the attendance page, as the page's script makes them.
    private func post(_ body: [String: ParentLockerJSON], label: StaticString) async throws -> ParentLockerJSON {
        var request = URLRequest(url: attendancePageURL)
        request.httpMethod = "POST"
        request.setValue("application/json;charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        request.httpBody = try encoder.encode(body)
        let data = try await send(request, label: label)
        guard let reply = try? JSONDecoder().decode(ParentLockerJSON.self, from: data), reply.objectValue != nil else {
            let text = Self.text(of: data)
            throw Self.looksLikeSignIn(text) ? ParentLockerError.signedOut : ParentLockerError.pageChanged
        }
        return reply
    }

    /// Sends `request` with the cookies, takes back any the reply sets, and
    /// reads the status. Returns the body of a 2xx reply.
    private func send(_ request: URLRequest, label: StaticString) async throws -> Data {
        var request = request
        request.httpShouldHandleCookies = false
        guard request.url?.host?.lowercased() == host, request.url?.scheme == "https" else {
            throw ParentLockerError.redirectedOffSite(host: request.url?.host ?? "")
        }
        if let url = request.url, let header = ParentLockerCookie.header(for: url, from: cookies, now: now()) {
            request.setValue(header, forHTTPHeaderField: "Cookie")
        }

        let redirects = RedirectRefusal()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: redirects)
        } catch {
            if let refused = redirects.refused { try handleRedirect(refused, label: label) }
            Self.logger.error("ParentLocker \(label, privacy: .public): no answer (\(error, privacy: .private))")
            throw ParentLockerError.unreachable
        }
        if let refused = redirects.refused { try handleRedirect(refused, label: label) }
        guard let http = response as? HTTPURLResponse else { throw ParentLockerError.unreachable }
        takeCookies(Self.cookies(in: http))
        if (200..<300).contains(http.statusCode) { return data }
        if (300..<400).contains(http.statusCode) {
            // A redirect the delegate never saw (a stub, say): read it the same way.
            let location = http.value(forHTTPHeaderField: "Location").flatMap { URL(string: $0, relativeTo: http.url) }
            try handleRedirect(.init(target: location?.absoluteURL, cookies: []), label: label)
        }
        Self.logger.error("ParentLocker \(label, privacy: .public): status \(http.statusCode, privacy: .public)")
        throw Self.error(forStatus: http.statusCode)
    }

    /// What a reply that isn't a success or a redirect means.
    static func error(forStatus status: Int) -> ParentLockerError {
        switch status {
        case 401, 403: .signedOut
        case 500...: .unreachable
        default: .pageChanged
        }
    }

    /// A refused redirect: the cookies it set are taken, and it reads as
    /// signed out when it stayed on the site, refused when it didn't.
    private func handleRedirect(_ refused: RedirectRefusal.Refused, label: StaticString) throws -> Never {
        takeCookies(refused.cookies)
        let target = refused.target?.host?.lowercased() ?? ""
        if target == host {
            Self.logger.info("ParentLocker \(label, privacy: .public): sent to sign in")
            throw ParentLockerError.signedOut
        }
        Self.logger.error("ParentLocker \(label, privacy: .public): refused a redirect off the site")
        throw ParentLockerError.redirectedOffSite(host: target)
    }

    /// The cookies a reply sets.
    static func cookies(in response: HTTPURLResponse) -> [ParentLockerCookie] {
        guard let url = response.url else { return [] }
        var fields: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let key = key as? String, let value = value as? String { fields[key] = value }
        }
        return HTTPCookie.cookies(withResponseHeaderFields: fields, for: url).map(ParentLockerCookie.init)
    }

    /// Lays a reply's cookies over the jar and says so when it changed.
    private func takeCookies(_ incoming: [ParentLockerCookie]) {
        guard !incoming.isEmpty else { return }
        let moment = now()
        let changed: [ParentLockerCookie]? = jar.withLock { stored in
            let merged = ParentLockerCookie.merge(incoming, into: stored, host: host, now: moment)
            guard merged != stored else { return nil }
            stored = merged
            return merged
        }
        if let changed { cookiesChanged?(changed) }
    }

    /// A reply's body as text, UTF-8 or else Latin-1.
    static func text(of data: Data) -> String {
        String(bytes: data, encoding: .utf8) ?? String(bytes: data, encoding: .isoLatin1) ?? ""
    }

    /// Whether a page is ParentLocker's sign-in page rather than the one asked for.
    static func looksLikeSignIn(_ text: String) -> Bool {
        text.contains("login-form") || text.contains("name=\"pass\"") || text.contains("process.php")
    }
}

/// Refuses every redirect for one request, keeping where it would have gone
/// and the reply that asked, so the transport can tell "sign in again" from
/// "refused".
private nonisolated final class RedirectRefusal: NSObject, URLSessionTaskDelegate, Sendable {
    struct Refused: Sendable {
        let target: URL?
        /// The cookies the redirecting reply set.
        let cookies: [ParentLockerCookie]
    }

    private let state = Mutex<Refused?>(nil)

    var refused: Refused? { state.withLock { $0 } }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        // The completion-handler form: Swift 6.4 crashes compiling the async
        // one's Objective-C thunk on a nonisolated class.
        let refused = Refused(target: request.url, cookies: ParentLockerHTTP.cookies(in: response))
        state.withLock { $0 = refused }
        completionHandler(nil)
    }
}
