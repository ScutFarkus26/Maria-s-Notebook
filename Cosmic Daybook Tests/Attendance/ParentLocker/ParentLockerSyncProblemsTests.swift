import Foundation
import Testing
@testable import CosmicDaybook

/// What the sync does when something is in the way (retries, someone else's
/// mark, being signed out in front or behind, a changed password, Sign Out
/// on another device) and what it writes: the day's send once and never in a
/// preview-only build, matches only from the guide, nothing from a preview.
@Suite("ParentLocker sync problems and saving")
@MainActor
struct ParentLockerSyncProblemsTests {

    typealias Device = ParentLockerTestDevice

    let site = FakeParentLocker()
    let clock = FakeParentLockerClock(Device.morning)

    private var saves: [String] { site.requests.filter { $0.hasPrefix("save") } }

    /// Everyone marked here as ParentLocker already holds them: Present.
    private func settled(_ device: Device) {
        for kid in site.kids.indices { site.kids[kid].markID = "701" }
        for child in Device.children { device.store.state.marks[child.id] = Device.mark(.present) }
    }

    /// The whole class marked, none of it in ParentLocker yet.
    private static let fullMarks: [UUID: ParentLockerPlanner.DayMark] = [
        Device.wren: Device.mark(.present), Device.june: Device.mark(.tardy),
        Device.marisol: Device.mark(.present), Device.odile: Device.mark(.present),
        Device.bea: Device.mark(.absent, reason: "sick")
    ]

    final class Flag {
        var value = false
    }

    // MARK: - Problems

    @Test("Couldn't reach ParentLocker: tries again after 30 s, 2 min and 5 min, then waits for the next change")
    func retriesThenWaits() async {
        let device = Device(site: site, clock: clock, sent: true)
        settled(device)
        site.failuresLeft = 4
        device.marks([Device.wren: Device.mark(.tardy)])
        clock.advance(by: 4)
        await device.sync.runDue()
        #expect(device.sync.status.state == .retrying)
        #expect(device.sync.status.message == "Couldn't reach ParentLocker. It'll try again.")
        for wait in ParentLockerSync.retryWaits {
            await expectRetry(after: wait, device)
        }
        #expect(device.sync.status.state == .gaveUp)
        #expect(device.sync.nextWake == nil, "nothing polls")
        #expect(saves.isEmpty)
        #expect(device.unsent.load()?.children == [Device.wren])

        device.marks([Device.june: Device.mark(.tardy)])
        clock.advance(by: 4)
        await device.sync.runDue()
        #expect(saves == ["save 5101"])
        #expect(Set(site.saves[0].entries.map(\.studentID)) == ["40001", "40002"])
        #expect(device.sync.status.state == .upToDate)
    }

    /// The next retry is due `wait` from now, and nothing goes before it.
    private func expectRetry(after wait: TimeInterval, _ device: Device) async {
        let due: Date = clock.now.addingTimeInterval(wait)
        #expect(device.sync.nextWake == due)
        let asked: Int = site.requests.count
        clock.advance(by: wait - 1)
        await device.sync.runDue()
        #expect(site.requests.count == asked, "not before its time")
        clock.advance(by: 1)
        await device.sync.runDue()
        #expect(site.requests.count > asked)
    }

    @Test("Someone else's change is reported, unless ParentLocker already holds what was sent")
    func conflicts() async {
        let device = Device(site: site, clock: clock, sent: true)
        settled(device)
        site.conflicts = [
            .init(studentID: "40001", desiredMarkID: "702", currentMarkID: "702"),
            .init(studentID: "40003", desiredMarkID: "703", currentMarkID: "702")
        ]
        device.marks([Device.wren: Device.mark(.tardy), Device.marisol: Device.mark(.absent)])
        clock.advance(by: 4)
        await device.sync.runDue()
        #expect(device.sync.status.problems == [
            ParentLockerStatus.conflictLine(name: "Marisol P", currentMark: "Late")
        ])
    }

    @Test("Signed out by the site while in front: signs back in by itself and carries on")
    func signsBackInInFront() async {
        let secrets = FakeParentLockerSecrets(cookie: "expired")
        let device = Device(site: site, clock: clock, secrets: secrets, sent: true)
        settled(device)
        device.marks([Device.wren: Device.mark(.tardy)])
        clock.advance(by: 4)
        await device.sync.runDue()
        #expect(site.signIns == 1)
        #expect(saves == ["save 5101"])
        #expect(secrets.savedCookies.map(\.value) == ["good"])
        #expect(device.sync.status.state == .upToDate)
    }

    @Test("Signed out while in the background: doesn't try, and sends on the way back")
    func noSignInInBackground() async {
        let inFront = Flag()
        let secrets = FakeParentLockerSecrets(cookie: "expired")
        let device = Device(site: site, clock: clock, secrets: secrets, inForeground: { inFront.value }, sent: true)
        settled(device)
        device.marks([Device.wren: Device.mark(.tardy)])
        clock.advance(by: 4)
        await device.sync.runDue()
        #expect(site.signIns == 0)
        #expect(saves.isEmpty)
        #expect(device.sync.status.state == .notSentYet)
        #expect(device.sync.status.message == "Couldn't send to ParentLocker yet. It'll send when you open the app.")
        #expect(device.unsent.load()?.children == [Device.wren])

        inFront.value = true
        device.sync.appReturned()
        await device.sync.runDue()
        #expect(site.signIns == 1)
        #expect(saves == ["save 5101"])
        #expect(device.unsent.load() == nil)
    }

    @Test("A password changed on the site asks the person to sign in again")
    func refusedPassword() async {
        let secrets = FakeParentLockerSecrets(cookie: "expired")
        let device = Device(site: site, clock: clock, secrets: secrets, sent: true)
        settled(device)
        site.password = "changed-on-the-site"
        device.marks([Device.wren: Device.mark(.tardy)])
        clock.advance(by: 4)
        await device.sync.runDue()
        #expect(device.sync.status.state == .passwordRefused)
        #expect(device.sync.status.message == "ParentLocker didn't take your saved password. Sign in again.")
        #expect(saves.isEmpty)
        #expect(secrets.savedCookies.isEmpty)
    }

    @Test("Sign Out on another device deletes the synced password, and this one signs out too")
    func passwordDeletedElsewhere() async throws {
        let secrets = FakeParentLockerSecrets()
        let device = Device(site: site, clock: clock, secrets: secrets, sent: true)
        #expect(device.sync.isSignedIn)
        try secrets.deletePassword(site: FakeParentLocker.host)

        let status = await device.sync.sendNow(day: Device.morning)
        #expect(status.state == .signedOut)
        #expect(!device.sync.isSignedIn)
        #expect(secrets.savedCookies.isEmpty)
        #expect(site.requests.isEmpty)

        // The same check on the way back to the app.
        let other = FakeParentLockerSecrets()
        let ipad = Device(site: site, clock: clock, secrets: other, sent: true)
        try other.deletePassword(site: FakeParentLocker.host)
        ipad.sync.appReturned()
        #expect(!ipad.sync.isSignedIn)
        #expect(other.savedCookies.isEmpty)
    }

    @Test("Signing in keeps the password only once ParentLocker took it, then sends what waited")
    func signInThenSend() async throws {
        let secrets = FakeParentLockerSecrets(password: nil, cookie: nil)
        let device = Device(site: site, clock: clock, secrets: secrets, marks: Self.fullMarks)
        #expect(device.sync.status.state == .signedOut)
        device.sync.closeArrivalSend(on: Device.morning)
        #expect(device.sync.nextWake == nil, "nothing goes until someone signs in")

        await #expect(throws: ParentLockerSignInError.passwordRefused) {
            try await device.sync.signIn(email: "guide@school.test", password: "mistyped")
        }
        #expect(try secrets.credential(site: FakeParentLocker.host) == nil)
        #expect(!device.sync.isSignedIn)

        try await device.sync.signIn(email: " guide@school.test ", password: site.password)
        #expect(try secrets.credential(site: FakeParentLocker.host)?.email == "guide@school.test")
        #expect(secrets.savedCookies.map(\.value) == ["good"])
        #expect(device.sync.isSignedIn)
        // It goes once Close Arrival's Undo has passed, never sooner.
        await device.sync.runDue()
        #expect(saves.isEmpty)
        clock.advance(by: ParentLockerSync.closeArrivalUndoWindow)
        await device.sync.runDue()
        #expect(saves == ["save 5101", "save 5102"])
        #expect(device.store.recordedSends.count == 1)
    }

    // MARK: - Saving

    @Test("A whole-class send records the day once; a preview-only build never saves or records")
    func sendRecordedOnce() async {
        let device = Device(site: site, clock: clock, marks: Self.fullMarks)
        await device.sync.sendNow(day: Device.morning)
        #expect(device.store.recordedSends.count == 1)
        device.marks([Device.odile: Device.mark(.tardy)])
        clock.advance(by: 4)
        await device.sync.runDue()
        #expect(device.store.recordedSends.count == 1)
        #expect(saves == ["save 5101", "save 5102", "save 5102"])

        let preview = FakeParentLocker()
        let debugBuild = Device(site: preview, clock: clock, policy: .previewOnly, marks: Self.fullMarks)
        debugBuild.sync.closeArrivalSend(on: Device.morning, after: 6)
        clock.advance(by: 6)
        await debugBuild.sync.runDue()
        #expect(preview.requests.contains("roster 5101"), "it reads")
        #expect(preview.saves.isEmpty)
        #expect(debugBuild.store.recordedSends.isEmpty)
        #expect(debugBuild.store.writtenMatches.isEmpty)
        #expect(debugBuild.sync.status.state == .previewed)
    }

    @Test("Name matches are written only on the guide's devices")
    func matchesOnlyByGuide() async {
        let guide = Device(site: site, clock: clock, marks: Self.fullMarks)
        await guide.sync.sendNow(day: Device.morning)
        #expect(guide.store.writtenMatches.count == 1)
        #expect(guide.store.writtenMatches.first?[Device.june] == "40002")
        #expect(guide.store.writtenMatches.first?.count == 5)

        let assistant = Device(site: FakeParentLocker(), clock: clock, role: .assistant, marks: Self.fullMarks)
        await assistant.sync.sendNow(day: Device.morning)
        #expect(assistant.store.writtenMatches.isEmpty)
        #expect(assistant.store.recordedSends.count == 1, "her send is recorded, as her email's is")
    }

    @Test("A preview writes nothing and leaves the status alone, whatever the method")
    func previewWritesNothing() async throws {
        let device = Device(site: site, clock: clock, marks: Self.fullMarks)
        device.store.state.method = .email
        let before = device.sync.status
        let report = try await device.sync.send(day: Device.morning, preview: true).get()
        #expect(report.wasPreview)
        #expect(report.classes.map(\.name) == ["Girls Middle School", "Upper Elementary Girls"])
        #expect(report.classes.flatMap(\.changes).count == 5)
        #expect(report.text.contains("Jun A: Late"))
        #expect(site.saves.isEmpty)
        #expect(device.store.recordedSends.isEmpty)
        #expect(device.store.writtenMatches.isEmpty)
        #expect(device.sync.status == before)

        // Sending for real needs ParentLocker picked.
        if case .failure(let failure) = await device.sync.send(day: Device.morning, preview: false) {
            #expect(failure.message == "Attendance goes by email. Pick ParentLocker in Settings to send it there.")
        } else {
            Issue.record("sent while email was picked")
        }
        #expect(site.saves.isEmpty)
    }

    @Test("A test run's default policy is preview only; only a Release build outside tests saves")
    func defaultPolicy() {
        #expect(ParentLockerSavePolicy.current == .previewOnly)
        let dependencies = ParentLockerSync.Dependencies(store: FakeParentLockerStore(state: ParentLockerDay()))
        #expect(dependencies.policy == .previewOnly)
        #expect(ParentLockerSavePolicy.resolve(isDebugBuild: false, environment: [:]) == .live)
        #expect(ParentLockerSavePolicy.resolve(isDebugBuild: true, environment: [:]) == .previewOnly)
        #expect(ParentLockerSavePolicy.resolve(
            isDebugBuild: false, environment: ["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"]
        ) == .previewOnly)
    }
}
