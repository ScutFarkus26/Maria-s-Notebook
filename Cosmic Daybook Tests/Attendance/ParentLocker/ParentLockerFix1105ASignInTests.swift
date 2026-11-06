import Foundation
import Testing
@testable import CosmicDaybook

/// Sign-ins, relaunches and timing, as the 2026-11-05 bug hunt found them
/// (report "ParentLocker in the Assistant bug hunt 2026-11-05", #15, #16,
/// #19, #21, #24, #25 and the engine review's leftovers): the sign-in prompt
/// after a relaunch and on an email day, Send to ParentLocker kept as itself,
/// each change synced in waiting its own minute, a background window iOS
/// ended, a run across midnight, cookies after Sign Out, the marks read at a
/// sign-in, and a hidden sign-in that ended cancelled. Over the fake site,
/// clock and keychain.
@Suite("ParentLocker fixes 2026-11-05: sign-ins and timing")
@MainActor
struct ParentLockerFix1105ASignInTests {

    typealias Device = ParentLockerTestDevice
    typealias Marks = Fix1105AMarks

    let site = FakeParentLocker()
    let clock = FakeParentLockerClock(Device.morning)

    private var saves: [String] { site.requests.filter { $0.hasPrefix("save") } }

    private static func signedOut() -> FakeParentLockerSecrets {
        FakeParentLockerSecrets(password: nil, cookie: nil)
    }

    /// Everyone Present here and in ParentLocker.
    private func settled(_ device: Device) {
        for kid in site.kids.indices { site.kids[kid].markID = "701" }
        device.store.state.marks = Marks.everyonePresent
    }

    // MARK: - #15 The sign-in prompt

    @Test("Siri's Close Arrival owed on a phone that needs a sign-in asks for one after a relaunch (#15)")
    func promptAfterRelaunch() {
        let unsent = ParentLockerMemoryUnsentStore()
        ParentLockerSync.oweCloseArrivalSend(on: Device.morning, in: unsent)
        let phone = Device(
            site: site, clock: clock, role: .assistant, secrets: Self.signedOut(), unsent: unsent, marks: Marks.closed
        )
        #expect(phone.sync.awaitsSignIn)
    }

    @Test("A switch to email ends the sign-in prompt (#15)")
    func emailEndsThePrompt() {
        let phone = Device(site: site, clock: clock, role: .assistant, secrets: Self.signedOut(), marks: Marks.closed)
        phone.sync.closeArrivalSend(on: Device.morning, after: 6)
        #expect(phone.sync.awaitsSignIn)
        phone.store.state.method = .email
        phone.sync.refreshStatus()
        #expect(!phone.sync.awaitsSignIn)
    }

    // MARK: - #16 Send to ParentLocker across a relaunch

    @Test("Send to ParentLocker waiting for a sign-in comes back as itself after a relaunch, and goes (#16)")
    func sendNowSurvivesARelaunch() async throws {
        let unsent = ParentLockerMemoryUnsentStore()
        let before = Device(
            site: site, clock: clock, secrets: Self.signedOut(), unsent: unsent,
            arrivalClosed: false, marks: Marks.everyonePresent
        )
        await before.sync.sendNow(day: Device.morning)
        #expect(before.sync.awaitsSignIn)
        before.sync.stop()

        let after = Device(
            site: site, clock: clock, secrets: Self.signedOut(), unsent: unsent,
            arrivalClosed: false, marks: Marks.everyonePresent
        )
        #expect(after.sync.awaitsSignIn, "it still asks for her sign-in")
        try await after.sync.signIn(email: "guide@school.test", password: site.password)
        await after.sync.runDue()
        #expect(saves == ["save 5101", "save 5102"])
        #expect(after.store.recordedSends.count == 1)
    }

    // MARK: - #19 Each change synced in waits its own minute

    @Test("Each change synced in waits its own minute (#19)")
    func eachImportWaitsItsOwnMinute() async {
        let device = Device(site: site, clock: clock, sent: true)
        settled(device)
        device.imports([Device.wren: Device.mark(.tardy)])
        await device.sync.baselineTask?.value
        clock.advance(by: 50)
        device.imports([Device.odile: Device.mark(.absent)])
        await device.sync.baselineTask?.value

        clock.advance(by: 10)
        await device.sync.runDue()
        #expect(saves == ["save 5101"], "only Wren's minute is up")
        clock.advance(by: ParentLockerSync.importedWait - 11)
        await device.sync.runDue()
        #expect(saves == ["save 5101"])
        clock.advance(by: 1)
        await device.sync.runDue()
        #expect(saves == ["save 5101", "save 5102"])
        #expect(site.mark(41002) == "703")
    }

    // MARK: - #21 A background window iOS ended

    @Test("After iOS ends a background window, the next send asks for a new one (#21)")
    func expiredWindowIsAskedForAgain() {
        let device = Device(site: site, clock: clock, sent: true)
        settled(device)
        device.marks([Device.wren: Device.mark(.tardy)])
        #expect(device.background.isHeld)
        // Time's up: iOS ends the window (or never gave one).
        device.background.isHeld = false
        device.marks([Device.june: Device.mark(.tardy)])
        #expect(device.background.isHeld)
    }

    // MARK: - #24 A run across midnight

    @Test("A run that ends on a new day leaves the line on the new day, not on Sending (#24)")
    func runAcrossMidnight() async {
        let device = Fix1105ADevice(site: site, clock: clock, sent: true, marks: Marks.everyonePresent)
        for kid in site.kids.indices { site.kids[kid].markID = "701" }
        device.marks([Device.wren: Device.mark(.tardy)])
        device.wire.duringRun = { clock.advance(by: 86_400) }
        clock.advance(by: ParentLockerSync.localQuiet)
        await device.sync.runDue()
        #expect(device.sync.status.state != .sending)
        #expect(device.sync.status.state == .idle)
    }

    // MARK: - #25 Cookies after Sign Out

    @Test("A reply landing after Sign Out keeps none of its cookies (#25)")
    func noCookiesAfterSignOut() async throws {
        let secrets = FakeParentLockerSecrets()
        let device = Fix1105ADevice(site: site, clock: clock, secrets: secrets, sent: true)
        _ = try await device.sync.loadRosters(day: Device.morning)
        let changed = try #require(device.wire.cookieCallbacks.last)
        changed([ParentLockerCookie(name: "PHPSESSID", value: "fresh", domain: FakeParentLocker.host)])
        #expect(secrets.savedCookies.map(\.value) == ["fresh"], "while signed in, a reply's cookies are kept")

        try device.sync.signOut()
        changed([ParentLockerCookie(name: "PHPSESSID", value: "late", domain: FakeParentLocker.host)])
        #expect(secrets.savedCookies.isEmpty)
    }

    // MARK: - The engine review's leftovers

    @Test("Signing in reads today's marks, for the changes synced in after it")
    func signInReadsTheMarks() async throws {
        let phone = Device(site: site, clock: clock, role: .assistant, secrets: Self.signedOut(), marks: Marks.closed)
        phone.sync.closeArrivalSend(on: Device.morning, after: 6)
        #expect(phone.sync.knownMarks == nil)
        try await phone.sync.signIn(email: "aide@school.test", password: site.password)
        #expect(phone.sync.knownMarks?[Device.wren] == Device.mark(.present))
    }

    @Test("A sign-in out of sight that ends cancelled stops signing in by itself, as \"needs you\" does")
    func hiddenSignInCancelled() async {
        let tries = Fix1105ABox(0)
        let device = Fix1105ADevice(
            site: site, clock: clock, secrets: FakeParentLockerSecrets(cookie: "expired"),
            sent: true, marks: Marks.everyonePresent,
            signIn: { _, _ in
                tries.value += 1
                throw ParentLockerSignInError.cancelled
            }
        )
        for kid in site.kids.indices { site.kids[kid].markID = "701" }
        device.marks([Device.wren: Device.mark(.tardy)])
        clock.advance(by: ParentLockerSync.localQuiet)
        await device.sync.runDue()
        #expect(device.sync.status.state == .needsYou)
        #expect(device.sync.signInNeedsYou)

        device.marks([Device.june: Device.mark(.tardy)])
        clock.advance(by: ParentLockerSync.localQuiet)
        await device.sync.runDue()
        #expect(tries.value == 1, "it isn't tried again by itself")
    }
}
