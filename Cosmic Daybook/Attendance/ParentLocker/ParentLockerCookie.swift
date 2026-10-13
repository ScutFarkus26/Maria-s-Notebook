import Foundation

/// One of the ParentLocker site's sign-in cookies, as the app keeps it: the
/// cookie's own properties, so it can live in this device's Keychain
/// (`ParentLockerKeychain`; `HTTPCookie` can't be archived) and go back on
/// each request by hand. Never logged: `description` hides the value.
nonisolated struct ParentLockerCookie: Codable, Sendable, Equatable, CustomStringConvertible {
    let name: String
    let value: String
    /// The host it was set for, or `.example.com` for a whole domain.
    let domain: String
    let path: String
    /// Nil for a cookie that lasts the session, which the app keeps anyway:
    /// Apple doesn't promise a web view's session cookies survive a relaunch.
    let expiresDate: Date?
    let isSecure: Bool
    let isHTTPOnly: Bool

    init(name: String, value: String, domain: String, path: String = "/",
         expiresDate: Date? = nil, isSecure: Bool = true, isHTTPOnly: Bool = true) {
        self.name = name
        self.value = value
        self.domain = domain.lowercased()
        self.path = path.isEmpty ? "/" : path
        self.expiresDate = expiresDate
        self.isSecure = isSecure
        self.isHTTPOnly = isHTTPOnly
    }

    init(_ cookie: HTTPCookie) {
        self.init(
            name: cookie.name, value: cookie.value, domain: cookie.domain, path: cookie.path,
            expiresDate: cookie.expiresDate, isSecure: cookie.isSecure, isHTTPOnly: cookie.isHTTPOnly
        )
    }

    var description: String { "ParentLockerCookie(\(name), domain: \(domain), value hidden)" }

    /// Whether the cookie belongs to `host` (its own, or a domain it is under).
    func applies(toHost host: String) -> Bool {
        let host = host.lowercased()
        guard domain.hasPrefix(".") else { return host == domain }
        return host == String(domain.dropFirst()) || host.hasSuffix(domain)
    }

    /// Whether the cookie goes with a request to `url` at `now`.
    func applies(to url: URL, now: Date) -> Bool {
        guard let host = url.host, applies(toHost: host), !isExpired(at: now) else { return false }
        if isSecure, url.scheme?.lowercased() != "https" { return false }
        let requestPath = url.path.isEmpty ? "/" : url.path
        return requestPath == path || requestPath.hasPrefix(path.hasSuffix("/") ? path : path + "/")
    }

    func isExpired(at now: Date) -> Bool {
        expiresDate.map { $0 <= now } ?? false
    }

    /// Which stored cookie this one replaces: the same name, domain and path.
    func sameSlot(as other: ParentLockerCookie) -> Bool {
        name == other.name && domain == other.domain && path == other.path
    }

    /// `stored` with `incoming` laid over it, as a browser does: a cookie
    /// replaces the one in its slot, and one already expired (the site's way
    /// of deleting it) removes it. Only cookies for `host` are kept.
    static func merge(
        _ incoming: [ParentLockerCookie], into stored: [ParentLockerCookie], host: String, now: Date
    ) -> [ParentLockerCookie] {
        var result = stored.filter { $0.applies(toHost: host) && !$0.isExpired(at: now) }
        for cookie in incoming where cookie.applies(toHost: host) {
            result.removeAll { $0.sameSlot(as: cookie) }
            if !cookie.isExpired(at: now) { result.append(cookie) }
        }
        return result
    }

    /// The `Cookie` header for a request to `url`, or nil when none applies.
    static func header(for url: URL, from cookies: [ParentLockerCookie], now: Date) -> String? {
        let pairs = cookies.filter { $0.applies(to: url, now: now) }
            .sorted { $0.path.count > $1.path.count }
            .map { "\($0.name)=\($0.value)" }
        return pairs.isEmpty ? nil : pairs.joined(separator: "; ")
    }
}
