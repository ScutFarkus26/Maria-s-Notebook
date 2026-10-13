import Foundation
import Observation
import OSLog
import WebKit

/// Why a sign-in through ParentLocker's form didn't finish, in plain words.
/// Never carries the password or the site's own text.
nonisolated enum ParentLockerSignInError: Error, Equatable, LocalizedError {
    /// The form came back: ParentLocker didn't take the email and password.
    case passwordRefused
    /// ParentLocker wants something only a person can do (new terms, a reset).
    case needsYou
    /// The site tried to go somewhere else; nothing was filled there.
    case offSite
    /// No answer in time, or none at all.
    case unreachable
    /// No sign-in form where one should be.
    case pageChanged
    /// The person closed the sheet.
    case cancelled

    var errorDescription: String? {
        switch self {
        case .passwordRefused: "ParentLocker didn't take that email and password. Check them and try again."
        case .needsYou: "ParentLocker needs you to finish signing in on its page."
        case .offSite, .pageChanged: ParentLockerError.pageChanged.errorDescription
        case .unreachable: "Couldn't reach ParentLocker. Check you're online and try again."
        case .cancelled: nil
        }
    }

    /// What a sync that was signing back in by itself makes of it.
    var syncError: Error {
        switch self {
        case .passwordRefused: ParentLockerSyncStop.passwordRefused
        case .needsYou, .cancelled: ParentLockerSyncStop.needsYou
        case .unreachable: ParentLockerError.unreachable
        case .offSite, .pageChanged: ParentLockerError.pageChanged
        }
    }
}

/// Signs in to ParentLocker through the site's own form, so the site sets its
/// cookies the way it expects (`plDeviceId` is filled by the page's script),
/// then hands back the site's cookies for the Keychain (plan "ParentLocker
/// attendance", Sign in once, kept private). Foreground only: a web view's
/// script stalls in the background.
///
/// The privacy rules, each kept here:
/// - The web view's store is `.nonPersistent()`: nothing of the site stays on
///   disk outside the Keychain, and the view is let go the moment it's done.
/// - The password goes into the form only as an argument to
///   `callAsyncJavaScript`, never in script text, and only on https, on the
///   exact site host, into `#login-form`. The script checks the page's own
///   location again before filling, and that the form posts to https on the
///   same host.
/// - After `cancel()`, nothing more is filled, and no cookies are handed back.
/// - A main-frame navigation anywhere but https on the site's host is
///   refused, and while the sign-in runs by itself it stops the sign-in.
/// - The web view is shown only when ParentLocker asks for something more
///   (`.needsYou`) and the caller lets it (the sign-in sheet).
@MainActor
@Observable
final class ParentLockerSignIn: NSObject, WKNavigationDelegate {

    enum Phase: Equatable {
        case idle
        case signingIn
        /// ParentLocker's page is showing, for the person to finish.
        case needsYou
        case finished
    }

    /// What the page in the web view is, as the scripts read it.
    enum Page: String {
        case signIn = "signin"
        case attendance
        case offSite = "offsite"
        case other
    }

    private(set) var phase: Phase = .idle
    /// The web view while a sign-in runs; shown only in `.needsYou`.
    @ObservationIgnored private(set) var webView: WKWebView?
    /// The site's host, cleaned.
    let host: String

    @ObservationIgnored private var loadsFinished = 0
    @ObservationIgnored private var waiter: (after: Int, continuation: CheckedContinuation<Void, Error>)?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var pendingFailure: ParentLockerSignInError?
    /// The person closed the sheet: every step after checks this.
    @ObservationIgnored private(set) var isCancelled = false

    /// How long a page may take before the sign-in gives up.
    nonisolated static let pageTimeout: TimeInterval = 30
    /// How long ParentLocker's own page waits for the person on each page.
    nonisolated static let personTimeout: TimeInterval = 600
    nonisolated static let attendancePath = "/sis/newattendance.php"

    private static let logger = Logger.attendance

    init(site: String) {
        host = AttendanceEmailLog.parentLockerHost(site)
    }

    // MARK: - Signing in

    /// Signs in with `credential` and returns the site's cookies. With
    /// `showsPagesWhenAsked`, a page ParentLocker puts in the way waits for
    /// the person (`.needsYou`); without, it throws `.needsYou`.
    func run(
        _ credential: ParentLockerKeychain.Credential, showsPagesWhenAsked: Bool
    ) async throws -> [ParentLockerCookie] {
        guard !isCancelled else { throw ParentLockerSignInError.cancelled }
        phase = .signingIn
        let webView = makeWebView()
        self.webView = webView
        defer { release() }
        do {
            var page = try await load(path: Self.attendancePath)
            if page == .other { page = try await load(path: "/") }
            if page == .signIn {
                let seen = loadsFinished
                guard try await fill(credential) else { throw ParentLockerSignInError.pageChanged }
                try await waitForPage(after: seen, timeout: Self.pageTimeout)
                page = try await readPage()
                if page == .other { page = try await load(path: Self.attendancePath) }
                if page == .signIn { throw ParentLockerSignInError.passwordRefused }
            }
            if page == .other {
                guard showsPagesWhenAsked else { throw ParentLockerSignInError.needsYou }
                phase = .needsYou
                page = try await waitForAttendancePage()
            }
            guard page == .attendance else { throw ParentLockerSignInError.offSite }
            let cookies = await siteCookies(in: webView)
            try checkCancelled()
            Self.logger.info("ParentLocker sign-in: done (\(cookies.count, privacy: .public) cookies)")
            phase = .finished
            return cookies
        } catch {
            phase = .idle
            // A script cut short by the cancel fails with WebKit's own error.
            let failure = isCancelled ? .cancelled : error as? ParentLockerSignInError ?? .unreachable
            Self.logger.error("ParentLocker sign-in: stopped (\(String(describing: failure), privacy: .public))")
            throw failure
        }
    }

    /// The person closed the sheet: the sign-in stops and the web view goes.
    func cancel() {
        isCancelled = true
        fail(.cancelled)
        release()
        phase = .idle
    }

    /// Throws once the person has cancelled: after every wait.
    private func checkCancelled() throws {
        if isCancelled { throw ParentLockerSignInError.cancelled }
    }

    // MARK: - Pages

    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 700), configuration: configuration)
        webView.navigationDelegate = self
        return webView
    }

    private func release() {
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        pendingFailure = nil
        loadsFinished = 0
    }

    private func url(path: String) -> URL? {
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = host
        parts.path = path
        return parts.url
    }

    /// After a cancel the web view is gone, so this and `readPage` stop there.
    private func load(path: String) async throws -> Page {
        guard let webView, let url = url(path: path) else { throw ParentLockerSignInError.cancelled }
        let seen = loadsFinished
        webView.load(URLRequest(url: url))
        try await waitForPage(after: seen, timeout: Self.pageTimeout)
        return try await readPage()
    }

    /// Waits for each page the person moves to until the attendance page
    /// loads, or until they've left a page alone for `personTimeout`.
    private func waitForAttendancePage() async throws -> Page {
        while true {
            try await waitForPage(after: loadsFinished, timeout: Self.personTimeout, onTimeout: .needsYou)
            let page = try await readPage()
            if page == .attendance { return page }
        }
    }

    private func readPage() async throws -> Page {
        guard let webView else { throw ParentLockerSignInError.cancelled }
        let result = try await webView.callAsyncJavaScript(
            Self.readPageScript, arguments: ["host": host], in: nil, contentWorld: .defaultClient
        )
        try checkCancelled()
        let page = (result as? String).flatMap(Page.init(rawValue:)) ?? .other
        if page == .offSite { throw ParentLockerSignInError.offSite }
        return page
    }

    /// Fills and submits the site's form in the sign-in's own web view, never
    /// once the person has cancelled. False when the page has no form to fill.
    private func fill(_ credential: ParentLockerKeychain.Credential) async throws -> Bool {
        try checkCancelled()
        guard let webView else { throw ParentLockerSignInError.cancelled }
        guard Self.isOnSite(webView.url, host: host) else { throw ParentLockerSignInError.offSite }
        let result = try await webView.callAsyncJavaScript(
            Self.fillScript, arguments: Self.fillArguments(credential, host: host),
            in: nil, contentWorld: .defaultClient
        )
        try checkCancelled()
        switch result as? String {
        case "submitted": return true
        case "offsite": throw ParentLockerSignInError.offSite
        default: return false
        }
    }

    private func siteCookies(in webView: WKWebView) async -> [ParentLockerCookie] {
        let all = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        return all.map(ParentLockerCookie.init).filter { $0.applies(toHost: host) }
    }

    // MARK: - Waiting for a page, without polling

    private func waitForPage(
        after seen: Int, timeout: TimeInterval, onTimeout: ParentLockerSignInError = .unreachable
    ) async throws {
        try checkCancelled()
        if let failure = pendingFailure {
            pendingFailure = nil
            throw failure
        }
        if loadsFinished > seen { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            waiter = (seen, continuation)
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                guard !Task.isCancelled else { return }
                self?.fail(onTimeout)
            }
        }
        try checkCancelled()
    }

    private func pageFinished() {
        loadsFinished += 1
        guard let waiting = waiter, loadsFinished > waiting.after else { return }
        waiter = nil
        timeoutTask?.cancel()
        waiting.continuation.resume()
    }

    private func fail(_ error: ParentLockerSignInError) {
        guard let waiting = waiter else {
            pendingFailure = pendingFailure ?? error
            return
        }
        waiter = nil
        timeoutTask?.cancel()
        waiting.continuation.resume(throwing: error)
    }

    // MARK: - WKNavigationDelegate

    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        let url = navigationAction.request.url
        if navigationAction.targetFrame?.isMainFrame ?? true {
            guard Self.isOnSite(url, host: host) else {
                decisionHandler(.cancel)
                // While the person is on the page, a link elsewhere just doesn't open.
                if phase != .needsYou { fail(.offSite) }
                return
            }
        } else if let scheme = url?.scheme?.lowercased(), scheme != "https", scheme != "about" {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        guard Self.isOnSite(webView.url, host: host) else { return fail(.offSite) }
        pageFinished()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
        navigationFailed(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
        navigationFailed(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        fail(.unreachable)
    }

    /// A load replaced by another (the page's own redirect) isn't a failure.
    private func navigationFailed(_ error: Error) {
        let error = error as NSError
        if error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled { return }
        // A navigation the policy refused reports as a frame load interruption.
        if error.domain == "WebKitErrorDomain", error.code == 102 { return }
        fail(.unreachable)
    }
}

// MARK: - Rules and scripts

extension ParentLockerSignIn {

    /// Only https on exactly the site's host.
    nonisolated static func isOnSite(_ url: URL?, host: String) -> Bool {
        guard let url, url.scheme?.lowercased() == "https", let urlHost = url.host?.lowercased() else { return false }
        return urlHost == host.lowercased()
    }

    /// What the fill script is given: the sign-in goes only as arguments.
    nonisolated static func fillArguments(
        _ credential: ParentLockerKeychain.Credential, host: String
    ) -> [String: Any] {
        ["email": credential.email, "password": credential.password, "host": host, "returnTo": attendancePath]
    }

    /// Reads what the page is. Its own location is checked first.
    nonisolated static let readPageScript = """
        if (location.protocol !== 'https:' || location.hostname.toLowerCase() !== host) { return 'offsite'; }
        const form = document.getElementById('login-form');
        if (form && form.querySelector('[name="pass"]')) { return 'signin'; }
        for (const script of document.scripts) {
            if (/\\bvar\\s+courses\\s*=/.test(script.text)) { return 'attendance'; }
        }
        return 'other';
        """

    /// Fills `#login-form` from its arguments and submits it as the button
    /// would, with "remember me" on and the attendance page to return to. It
    /// fills nothing unless the page is https on the site's host and the form
    /// posts there too (read from the attribute: a field named "action"
    /// would hide the property).
    nonisolated static let fillScript = """
        if (location.protocol !== 'https:' || location.hostname.toLowerCase() !== host) { return 'offsite'; }
        const form = document.getElementById('login-form');
        const user = form && form.querySelector('[name="user"]');
        const pass = form && form.querySelector('[name="pass"]');
        if (!user || !pass) { return 'noform'; }
        let target;
        try {
            target = new URL(form.getAttribute('action') || location.href, location.href);
        } catch (e) {
            return 'offsite';
        }
        if (target.protocol !== 'https:' || target.hostname.toLowerCase() !== host) { return 'offsite'; }
        const put = (field, value) => {
            field.value = value;
            field.dispatchEvent(new Event('input', { bubbles: true }));
            field.dispatchEvent(new Event('change', { bubbles: true }));
        };
        put(user, email);
        put(pass, password);
        let remember = form.querySelector('[name="remember"]');
        if (!remember) {
            remember = document.createElement('input');
            remember.type = 'hidden';
            remember.name = 'remember';
            form.appendChild(remember);
        }
        if (remember.type === 'checkbox') { remember.checked = true; } else { remember.value = '1'; }
        const back = form.querySelector('[name="return_to"]');
        if (back && !back.value) { back.value = returnTo; }
        if (typeof form.requestSubmit === 'function') { form.requestSubmit(); } else { form.submit(); }
        return 'submitted';
        """
}
