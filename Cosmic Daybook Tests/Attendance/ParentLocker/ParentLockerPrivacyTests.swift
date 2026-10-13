import Foundation
import OSLog
import Testing
@testable import CosmicDaybook

/// The sign-in's privacy rules (plan "ParentLocker attendance", Privacy
/// rules): the password goes into the site's form only as a script argument,
/// only on https on the exact site host, and never shows in a status line,
/// an error, a report, the log or the preferences. The wording the screens
/// show is pinned here too.
@Suite("ParentLocker privacy and wording")
@MainActor
struct ParentLockerPrivacyTests {

    static let secret = "pl-Secret-7731"

    @Test("The password goes into the form only as an argument, on https and the site's exact host")
    func passwordIsAnArgument() {
        let credential = ParentLockerKeychain.Credential(email: "guide@school.test", password: Self.secret)
        let host = FakeParentLocker.host
        let arguments = ParentLockerSignIn.fillArguments(credential, host: host)
        #expect(arguments["password"] as? String == Self.secret)
        #expect(Set(arguments.keys) == ["email", "password", "host", "returnTo"])
        #expect(!ParentLockerSignIn.fillScript.contains(Self.secret))
        #expect(ParentLockerSignIn.fillScript.contains("put(pass, password)"))
        #expect(ParentLockerSignIn.fillScript.hasPrefix(
            "if (location.protocol !== 'https:' || location.hostname.toLowerCase() !== host)"
        ))
        #expect(ParentLockerSignIn.fillScript.contains("document.getElementById('login-form')"))
        #expect(ParentLockerSignIn.readPageScript.hasPrefix("if (location.protocol !== 'https:'"))

        #expect(ParentLockerSignIn.isOnSite(URL(string: "https://\(host)/process.php"), host: host))
        #expect(ParentLockerSignIn.isOnSite(URL(string: "https://\(host.uppercased())/"), host: host))
        #expect(!ParentLockerSignIn.isOnSite(URL(string: "http://\(host)/process.php"), host: host))
        #expect(!ParentLockerSignIn.isOnSite(URL(string: "https://\(host).elsewhere.test/"), host: host))
        #expect(!ParentLockerSignIn.isOnSite(URL(string: "https://other.\(host)/"), host: host))
        #expect(!ParentLockerSignIn.isOnSite(URL(string: "https://accounts.google.com/"), host: host))
        #expect(!ParentLockerSignIn.isOnSite(nil, host: host))
    }

    @Test("The password never shows in a status line, an error, a report, the log or the preferences")
    func passwordNeverShows() async throws {
        let started = Date()
        let morning = ParentLockerTestDevice.morning
        let site = FakeParentLocker()
        site.password = Self.secret
        let secrets = FakeParentLockerSecrets(password: Self.secret, cookie: "expired")
        let device = ParentLockerTestDevice(
            site: site, clock: FakeParentLockerClock(morning), secrets: secrets,
            marks: [ParentLockerTestDevice.wren: ParentLockerTestDevice.mark(.tardy)]
        )
        var seen: [String] = []
        func noteStatus(_ status: ParentLockerStatus) {
            seen += [status.message, status.line(sentSummary: "Sent to ParentLocker 8:47 AM by you"), status.details]
                .compactMap { $0 } + status.problems + [String(describing: status)]
        }
        func noteResult(_ result: Result<ParentLockerReport, ParentLockerSendFailure>) {
            switch result {
            case .success(let report): seen += [report.text, String(describing: report)]
            case .failure(let failure): seen += [failure.message, failure.details ?? "", String(describing: failure)]
            }
        }

        // Signing back in, sending, previewing.
        noteStatus(await device.sync.sendNow(day: morning))
        noteResult(await device.sync.send(day: morning, preview: true))
        // A password the site no longer takes, and a site that doesn't answer.
        try secrets.saveCookies([], site: FakeParentLocker.host)
        site.password = "changed-on-the-site"
        noteStatus(await device.sync.sendNow(day: morning))
        noteResult(await device.sync.send(day: morning, preview: true))
        site.failuresLeft = 1
        noteResult(await device.sync.send(day: morning, preview: true))
        // Every error's own words, as the screens would show them.
        let errors: [Error] = [
            ParentLockerSignInError.passwordRefused, ParentLockerSignInError.needsYou,
            ParentLockerSignInError.offSite, ParentLockerSignInError.unreachable, ParentLockerError.signedOut,
            ParentLockerError.refused(message: "Bad request"), ParentLockerKeychain.KeychainError.write(-25_300)
        ]
        seen += errors.map { AppErrorMessages.userMessage(for: $0, context: "signing in to ParentLocker") }
        let credential = ParentLockerKeychain.Credential(email: "guide@school.test", password: Self.secret)
        seen.append(String(describing: credential))
        seen.append(String(describing: UserDefaults.standard.dictionaryRepresentation()))

        #expect(seen.count > 20)
        for text in seen {
            #expect(!text.contains(Self.secret))
        }

        try expectLogClean(since: started)
    }

    /// This process's log since `started`: the runs logged, and none of it carries the password.
    private func expectLogClean(since started: Date) throws {
        let log = try OSLogStore(scope: .currentProcessIdentifier)
        let since = log.position(date: started)
        let logged = try log.getEntries(at: since, matching: NSPredicate(
            format: "composedMessage CONTAINS %@", "ParentLocker: a send didn't go"
        ))
        #expect(logged.contains { _ in true }, "the failures were logged")
        let leaks = try log.getEntries(
            at: since, matching: NSPredicate(format: "composedMessage CONTAINS %@", Self.secret)
        )
        #expect(!leaks.contains { _ in true })
    }

    // MARK: - Wording

    @Test("The status line joins the day's send with where things stand")
    func statusLine() {
        let sent = "Sent to ParentLocker 8:47 AM by Sarah"
        #expect(ParentLockerStatus(state: .upToDate).line(sentSummary: sent) == sent + " · up to date")
        #expect(ParentLockerStatus(state: .sending).line(sentSummary: sent) == sent + " · sending…")
        #expect(ParentLockerStatus(state: .idle).line(sentSummary: sent) == sent)
        #expect(ParentLockerStatus(state: .retrying).line(sentSummary: sent)
            == sent + ". Couldn't reach ParentLocker. It'll try again.")
        #expect(ParentLockerStatus(state: .waitingForArrival).line(sentSummary: nil)
            == "Attendance goes to ParentLocker when arrival closes.")
        #expect(ParentLockerStatus(state: .off).line(sentSummary: nil) == nil)
        #expect(ParentLockerStatus(state: .retrying).isTrouble)
        #expect(!ParentLockerStatus(state: .upToDate).isTrouble)
    }

    @Test("What a plan leaves alone reads as plain lines, the unmatched gathered into one")
    func problemLines() {
        let maya = UUID()
        let etty = UUID()
        let ada = UUID()
        let names = [maya: "Maya S", etty: "Etty R", ada: "Ada F"]
        let skipped: [ParentLockerPlanner.Skip] = [
            .init(childID: maya, reason: .locked(currentMark: "Absent")),
            .init(childID: etty, reason: .cantClear(currentMark: "Present")),
            .init(childID: ada, reason: .unmatched),
            .init(childID: maya, reason: .unmarked)
        ]
        let guide = ParentLockerStatus.problems(for: skipped, names: { names[$0] ?? "" }, isGuide: true)
        #expect(guide == [
            "Ada F isn't matched to a child in ParentLocker yet. Match them in Settings › Match Names.",
            "The office already marked Maya S Absent.",
            "Etty R is still Present in ParentLocker. ParentLocker can't clear a mark; " +
                "mark her Late or Absent if that's right."
        ])
        let assistant = ParentLockerStatus.problems(
            for: [
                .init(childID: ada, reason: .unmatched),
                .init(childID: etty, reason: .ambiguous(studentIDs: ["1", "2"]))
            ],
            names: { names[$0] ?? "" }, isGuide: false
        )
        #expect(assistant == [
            "2 children aren't matched in ParentLocker yet: Ada F, Etty R. Your guide can match them in Settings."
        ])
    }
}
