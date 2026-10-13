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
            "Ada F isn't matched to a child in ParentLocker yet. Match them in Settings › Messages › Match Names.",
            "The office already marked Maya S Absent.",
            "Etty R is still Present in ParentLocker, which can't remove a mark. " +
                "If that's wrong, give Etty R the right mark here."
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

    @Test("Why a run stopped, a test copy, the Keychain and Match Names read as plain sentences")
    func plainSentences() {
        #expect(ParentLockerSyncStop.passwordRefused.message
            == "ParentLocker didn't take your saved password. Sign in again.")
        #expect(ParentLockerSyncStop.keychain.message
            == "Couldn't use your saved ParentLocker sign-in on this device. Restart the device and try again.")
        // The screens that pass a stop through `AppErrorMessages` get the same sentence.
        let stops: [ParentLockerSyncStop] = [.signedOut, .notSentYet, .passwordRefused, .needsYou, .keychain]
        for stop in stops {
            #expect(AppErrorMessages.userMessage(for: stop, context: "reading ParentLocker") == stop.message)
            #expect(ParentLockerStatus.failure(for: stop, lastSyncAt: nil).message == stop.message)
        }
        #expect(ParentLockerStatus(state: .previewed).message
            == "This test copy of the app only previews. Nothing was sent to ParentLocker.")
        #expect(ParentLockerKeychain.KeychainError.read(-25_308).errorDescription
            == "Couldn't read your saved ParentLocker sign-in on this device. Restart the device and try again.")
        #expect(ParentLockerKeychain.KeychainError.write(-25_308).errorDescription
            == "Couldn't save your ParentLocker sign-in on this device. Try again.")
        #expect(ParentLockerSignInError.unreachable.errorDescription
            == "Couldn't reach ParentLocker. Check you're online and try again.")

        #expect(ParentLockerMatchView.refusal(policy: .previewOnly, role: .leadGuide)
            == "This test copy of the app only previews, so the match wasn't saved.")
        #expect(ParentLockerMatchView.refusal(policy: .live, role: .assistant) == "Only the guide can match names.")
        #expect(ParentLockerMatchView.refusal(policy: .live, role: .leadGuide) == nil)
        #expect(ParentLockerMatchView.saveFailed == "Couldn't save the match. Try again.")
    }

    @Test("A report says which classes it skipped and why, and when none holds the children")
    func reportWording() {
        let art = ParentLockerCourse(
            courseID: 1, name: "Art", period: 2, attendanceReportID: "9", isDailyAttendance: false
        )
        let chess = ParentLockerCourse(courseID: 2, name: "Chess", period: 3, attendanceReportID: "8",
                                       reportStatus: "not_expected")
        let (load, skipped) = ParentLockerSync.coursesToLoad([art, chess, FakeParentLocker.middle], isToday: true)
        #expect(load == [FakeParentLocker.middle])
        #expect(skipped == [
            "Skipped Art: it doesn't take daily attendance.", "Skipped Chess: no attendance is expected today."
        ])
        let report = ParentLockerReport(
            day: ParentLockerTestDevice.morning, wasPreview: true, classes: [], problems: [],
            classesLeftAlone: skipped, savedCount: 0
        )
        #expect(report.text.contains("None of your ParentLocker classes has any of these children."))
        #expect(report.text.contains("\nSkipped Art: it doesn't take daily attendance."))
        #expect(!report.text.contains("Left alone"))
    }
}
