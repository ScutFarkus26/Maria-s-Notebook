import Foundation
import Testing
import WebKit
@testable import CosmicDaybook

/// The sign-in's own guards (2026-10-13 bug check): the fill script fills
/// only a form that posts to https on the site's host, and a sign-in the
/// person cancelled stops without filling or handing back anything. The
/// script runs in a real web view on a page loaded from a string, so
/// nothing goes over the network.
@Suite("ParentLocker sign-in form and cancel", .timeLimit(.minutes(1)))
@MainActor
struct ParentLockerSignInTests {

    private static let credential = ParentLockerKeychain.Credential(
        email: "guide@school.test", password: "made-up-password"
    )

    /// A sign-in form as ParentLocker's page has it, posting to `action`
    /// (none: the page itself). Submitting never leaves the page.
    private static func page(action: String?, extraField: String = "") -> String {
        let actionAttribute = action.map { " action=\"\($0)\"" } ?? ""
        return """
            <html><body>
            <form id="login-form" method="post"\(actionAttribute) onsubmit="event.preventDefault()">
            <input name="user"><input name="pass" type="password">\(extraField)
            </form>
            </body></html>
            """
    }

    /// Runs the fill script on `html`, loaded as if from https on the site's
    /// host. Returns the script's answer and the email field afterward.
    private func fill(_ html: String) async throws -> (answer: String?, email: String?) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 480), configuration: configuration)
        let loaded = PageLoaded()
        webView.navigationDelegate = loaded
        webView.loadHTMLString(html, baseURL: URL(string: "https://\(FakeParentLocker.host)/sis/newattendance.php"))
        await loaded.wait()
        let answer = try await webView.callAsyncJavaScript(
            ParentLockerSignIn.fillScript,
            arguments: ParentLockerSignIn.fillArguments(Self.credential, host: FakeParentLocker.host),
            in: nil, contentWorld: .defaultClient
        )
        let email = try await webView.callAsyncJavaScript(
            "return document.querySelector('[name=\"user\"]').value;", arguments: [:], in: nil, contentWorld: .page
        )
        return (answer as? String, email as? String)
    }

    @Test("The form is filled only when it posts to https on the site's own host")
    func fillsOnlyTheSitesForm() async throws {
        for action in ["/process.php", "https://\(FakeParentLocker.host)/process.php", nil] {
            let result = try await fill(Self.page(action: action))
            #expect(result.answer == "submitted", "\(action ?? "no action")")
            #expect(result.email == Self.credential.email)
        }
        for action in [
            "https://elsewhere.example/collect", "http://\(FakeParentLocker.host)/process.php",
            "https://\(FakeParentLocker.host).elsewhere.example/", "//elsewhere.example/collect"
        ] {
            let result = try await fill(Self.page(action: action))
            #expect(result.answer == "offsite", "\(action)")
            #expect(result.email == "", "nothing filled for \(action)")
        }
        // A field named "action" can't hide where the form really posts.
        let hidden = try await fill(Self.page(
            action: "https://elsewhere.example/collect", extraField: "<input type=\"hidden\" name=\"action\">"
        ))
        #expect(hidden.answer == "offsite")
        #expect(hidden.email == "")
    }

    @Test("A sign-in cancelled before it starts, or while a page loads, stops with nothing")
    func cancelStops() async {
        let early = ParentLockerSignIn(site: FakeParentLocker.host)
        early.cancel()
        await #expect(throws: ParentLockerSignInError.cancelled) {
            try await early.run(Self.credential, showsPagesWhenAsked: false)
        }
        #expect(early.webView == nil)

        let midway = ParentLockerSignIn(site: FakeParentLocker.host)
        let running = Task { try await midway.run(Self.credential, showsPagesWhenAsked: true) }
        while midway.webView == nil { await Task.yield() }
        #expect(midway.phase == .signingIn)
        midway.cancel()
        await #expect(throws: ParentLockerSignInError.cancelled) { try await running.value }
        #expect(midway.isCancelled)
        #expect(midway.webView == nil)
        #expect(midway.phase == .idle)
    }
}

/// Hears a web view finish its page.
@MainActor
private final class PageLoaded: NSObject, WKNavigationDelegate {
    private var finished = false
    private var waiting: CheckedContinuation<Void, Never>?

    func wait() async {
        if !finished { await withCheckedContinuation { waiting = $0 } }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        finished = true
        waiting?.resume()
        waiting = nil
    }
}
