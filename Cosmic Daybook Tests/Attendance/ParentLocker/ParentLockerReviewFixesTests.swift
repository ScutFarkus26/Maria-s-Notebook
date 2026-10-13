import Foundation
import Testing
@testable import CosmicDaybook

/// What the review of the 2026-10-13 bug-check fixes found in the engine:
/// the class lists read for changes synced in (once a day per child, and
/// never alongside a run), Reset Day stopping a waiting Close Arrival & Send,
/// and a refused password reading as needing a sign-in. Over the fake site,
/// clock and keychain.
@Suite("ParentLocker review fixes")
@MainActor
struct ParentLockerReviewFixesTests {

    typealias Device = ParentLockerTestDevice

    let site = FakeParentLocker()
    let clock = FakeParentLockerClock(Device.morning)

    private var saves: [String] { site.requests.filter { $0.hasPrefix("save") } }
    private var classListReads: Int { site.requests.filter { $0 == "courses" }.count }

    private static let automatic = Device.mark(.absent, reason: AttendanceDeduplication.automaticAbsenceRaw)

    /// The class as Close Arrival finds it: everyone in but Bea, who it marks absent.
    private static let closed: [UUID: ParentLockerPlanner.DayMark] = [
        Device.wren: Device.mark(.present), Device.june: Device.mark(.present),
        Device.marisol: Device.mark(.tardy), Device.odile: Device.mark(.present),
        Device.bea: automatic
    ]

    /// Everyone marked here as ParentLocker already holds them: Present.
    private func settled(_ device: Device) {
        for kid in site.kids.indices { site.kids[kid].markID = "701" }
        for child in Device.children { device.store.state.marks[child.id] = Device.mark(.present) }
    }

    // MARK: - B4 The class lists read for changes synced in

    @Test("A child ParentLocker doesn't hold sets off one read of the class lists a day, however often they sync in")
    func unheldChildReadOncePerDay() async {
        let mac = Device(site: site, clock: clock, sent: true)
        settled(mac)
        // Ines isn't in ParentLocker; Wren was set to "Not matched".
        let ines = ParentLockerPlanner.Child(id: UUID(), firstName: "Ines", lastName: "Quill")
        mac.store.state.children.append(ines)
        mac.store.state.children[0] = ParentLockerPlanner.Child(
            id: Device.wren, firstName: "Wren", lastName: "Halloway", parentLockerID: ParentLockerPlanner.notMatchedID
        )
        mac.imports([ines.id: Device.mark(.tardy), Device.wren: Device.mark(.tardy)])
        await mac.sync.baselineTask?.value
        #expect(classListReads == 1)
        clock.advance(by: ParentLockerSync.importedWait)
        await mac.sync.runDue()
        #expect(classListReads == 2, "the change itself reads them once")

        // Their next changes, and a matched child's after the first read: no more reads.
        mac.imports([ines.id: Device.mark(.absent, reason: "sick"), Device.wren: Device.mark(.present)])
        await mac.sync.baselineTask?.value
        mac.imports([Device.odile: Device.mark(.tardy)])
        await mac.sync.baselineTask?.value
        #expect(classListReads == 2)
        #expect(saves.isEmpty)

        // A new day starts afresh.
        clock.advance(by: 86_400)
        mac.sync.noteChanges([ines.id], imported: true, on: clock.now)
        await mac.sync.baselineTask?.value
        #expect(classListReads == 3)
    }

    @Test("The class lists for a change synced in are read after a run, so a wrong password is tried once")
    func baselineReadWaitsForRun() async throws {
        // No saved cookies, and a password the site no longer takes.
        let secrets = FakeParentLockerSecrets(cookie: nil)
        let device = Device(site: site, clock: clock, secrets: secrets, sent: true)
        settled(device)
        site.password = "changed-on-the-site"
        site.signInYields = 50
        device.marks([Device.wren: Device.mark(.tardy)])
        clock.advance(by: ParentLockerSync.localQuiet)
        let running = Task { await device.sync.runDue() }
        for _ in 0..<1_000 where device.sync.activeRun == nil { await Task.yield() }
        try #require(device.sync.activeRun != nil)

        // A change syncs in while the run is signing in.
        device.imports([Device.odile: Device.mark(.absent, reason: "sick")])
        await running.value
        await device.sync.baselineTask?.value
        #expect(site.signIns == 1)
        #expect(device.sync.savedPasswordRefused)
        #expect(saves.isEmpty)
    }

    @Test("A run waits for the class lists being read for a change synced in")
    func runWaitsForBaselineRead() async throws {
        let secrets = FakeParentLockerSecrets(cookie: nil)
        let device = Device(site: site, clock: clock, secrets: secrets, sent: true)
        settled(device)
        site.signInYields = 50
        device.imports([Device.odile: Device.mark(.absent, reason: "sick")])
        for _ in 0..<1_000 where !device.sync.readingBaseline { await Task.yield() }
        try #require(device.sync.readingBaseline)

        // This device's own change comes due while the read is signing in.
        device.marks([Device.wren: Device.mark(.tardy)])
        clock.advance(by: ParentLockerSync.localQuiet)
        await device.sync.runDue()
        #expect(site.signIns == 1, "the run uses the read's sign-in")
        #expect(site.requests.prefix(3) == ["courses", "roster 5101", "roster 5102"])
        #expect(site.saves.last?.entries.map(\.studentID) == ["40001"])
    }

    // MARK: - B1 Reset Day

    @Test("Close Arrival & Send doesn't go once Reset Day cleared every mark, and arrival is open here again")
    func resetDayStopsTheSend() async {
        let device = Device(site: site, clock: clock, marks: Self.closed)
        device.sync.closeArrivalSend(on: Device.morning, after: 6)
        // Reset Day (on another device, synced in): no marks, no automatic absence.
        device.store.state.marks = Device.children.reduce(into: [:]) { $0[$1.id] = Device.mark(.unmarked) }
        device.store.state.arrivalClosed = false
        clock.advance(by: 6)
        await device.sync.runDue()
        #expect(saves.isEmpty)
        #expect(device.store.recordedSends.isEmpty)
        #expect(device.sync.undoEndsAt == nil)
        #expect(device.unsent.load() == nil, "arrival isn't closed here any more")

        // A child marked after the reset waits for arrival to close again.
        #expect(!device.sync.isAfter(device.store.day(Device.morning, withChildren: false), on: Device.morning))
        device.marks([Device.wren: Device.mark(.present)])
        clock.advance(by: ParentLockerSync.localQuiet)
        await device.sync.runDue()
        #expect(saves.isEmpty)
    }

    // MARK: - B2 A refused password needs a sign-in

    @Test("A refused saved password reads as needing a sign-in, until a new one is saved")
    func refusedPasswordNeedsSignIn() async throws {
        let secrets = FakeParentLockerSecrets(cookie: "expired")
        let device = Device(site: site, clock: clock, secrets: secrets, sent: true)
        settled(device)
        #expect(!device.sync.needsSignIn)
        site.password = "changed-on-the-site"
        device.marks([Device.wren: Device.mark(.tardy)])
        clock.advance(by: ParentLockerSync.localQuiet)
        await device.sync.runDue()
        #expect(device.sync.isSignedIn, "the password is still saved")
        #expect(device.sync.needsSignIn)

        try await device.sync.signIn(email: "guide@school.test", password: site.password)
        #expect(!device.sync.needsSignIn)

        try device.sync.signOut()
        #expect(device.sync.needsSignIn)
    }
}
