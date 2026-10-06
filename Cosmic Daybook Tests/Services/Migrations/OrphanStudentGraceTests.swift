import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// A student can be missing for a moment — her shared row deleted before the private copy
/// that replaces it arrives. The launch cleanups only strip an id missing on passes a day
/// apart, with an import from iCloud since it went missing (`OrphanStudentGrace`).
@Suite("Orphan student grace")
@MainActor
struct OrphanStudentGraceTests {
    private typealias Fixture = LaunchRepairFixture
    private let start = Date(timeIntervalSinceReferenceDate: 780_000_000)

    @Test("An id is acted on only once it has been missing a full day, with an import since")
    func graceRule() {
        let imported = start.addingTimeInterval(7_200)
        let grace = OrphanStudentGrace(ledger: [:], now: start)
        #expect(grace.admit(missing: ["A", "B"], validIDs: []).isEmpty)
        #expect(grace.ledger == ["A": start, "B": start])

        let hourLater = OrphanStudentGrace(ledger: grace.ledger, now: start.addingTimeInterval(3_600))
        #expect(hourLater.admit(missing: ["A", "B"], validIDs: []).isEmpty)

        let dayLater = OrphanStudentGrace(
            ledger: hourLater.ledger, now: start.addingTimeInterval(86_400), lastImport: imported
        )
        #expect(dayLater.admit(missing: ["A", "B"], validIDs: []) == ["A", "B"])
    }

    @Test("An import that finished before the id went missing doesn't count")
    func importBeforeFirstSightingDoesNotCount() {
        let grace = OrphanStudentGrace(ledger: [:], now: start)
        _ = grace.admit(missing: ["A"], validIDs: [])

        let dayLater = OrphanStudentGrace(
            ledger: grace.ledger, now: start.addingTimeInterval(86_400), lastImport: start.addingTimeInterval(-60)
        )
        #expect(dayLater.admit(missing: ["A"], validIDs: []).isEmpty)
        #expect(dayLater.ledger["A"] == start)
    }

    @Test("Ids are compared trimmed and upper-cased, an older ledger's spellings included")
    func idsAreNormalized() {
        let grace = OrphanStudentGrace(
            ledger: ["ab-1": start, "AB-1": start.addingTimeInterval(60)], now: start.addingTimeInterval(86_400),
            lastImport: start.addingTimeInterval(3_600)
        )
        #expect(grace.ledger == ["AB-1": start])
        #expect(OrphanStudentGrace.normalizedID("  ab-1\n") == "AB-1")
        #expect(grace.admit(missing: ["AB-1"], validIDs: []) == ["AB-1"])
    }

    @Test("The check-in ledger is kept apart from the students'")
    func ledgersAreSeparate() throws {
        let suite = "OrphanStudentGraceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        OrphanStudentGrace.save(["S": start], to: defaults)
        OrphanStudentGrace.save(["W": start], to: defaults, kind: .checkInWork)
        #expect(OrphanStudentGrace.load(from: defaults) == ["S": start])
        #expect(OrphanStudentGrace.load(from: defaults, kind: .checkInWork) == ["W": start])
    }

    @Test("An id that turns up again is forgotten, so a later absence starts over")
    func returningIDForgotten() {
        let first = OrphanStudentGrace(ledger: [:], now: start)
        _ = first.admit(missing: ["A"], validIDs: [])
        let back = OrphanStudentGrace(ledger: first.ledger, now: start.addingTimeInterval(3_600))
        #expect(back.admit(missing: [], validIDs: ["A"]).isEmpty)
        #expect(back.ledger.isEmpty)

        let gone = OrphanStudentGrace(ledger: back.ledger, now: start.addingTimeInterval(2 * 86_400))
        #expect(gone.admit(missing: ["A"], validIDs: []).isEmpty) // first seen now, not two days ago
    }

    @Test("The ledger round-trips through defaults")
    func persistence() throws {
        let suite = "OrphanStudentGraceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        OrphanStudentGrace.save(["A": start], to: defaults)
        #expect(OrphanStudentGrace.load(from: defaults) == ["A": start])
    }

    @Test("The launch pass holds off a day and an import, then cleans exactly as before")
    func launchPassWaitsADay() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        try Fixture.seed(stack.viewContext)
        let seeded = Fixture.snapshot(of: stack.viewContext)
        let imported = start.addingTimeInterval(7_200)
        let lastImport: @Sendable (ImportStoreKind) -> Date? = { $0 == .privateStore ? imported : nil }

        let first = await MigrationRunner.runPass(
            on: stack.newBackgroundContext(), includeIntegrityRepairs: true, firstDownloadPending: false,
            orphanGraceLedger: [:], lastImport: lastImport, now: start
        ) { _ in [:] }
        #expect(first.workRowsCleaned == 0)
        let afterFirst = Fixture.snapshot(of: stack.viewContext)
        #expect(afterFirst.workStudents == seeded.workStudents)
        #expect(afterFirst.participantStudents == seeded.participantStudents)
        #expect(afterFirst.assignmentStudents == seeded.assignmentStudents)
        let ledger = try #require(first.orphanGraceLedger)
        #expect(!ledger.isEmpty)

        let soon = await MigrationRunner.runPass(
            on: stack.newBackgroundContext(), includeIntegrityRepairs: true, firstDownloadPending: false,
            orphanGraceLedger: ledger, lastImport: lastImport, now: start.addingTimeInterval(3_600)
        ) { _ in [:] }
        #expect(soon.workRowsCleaned == 0)

        let nextDay = await MigrationRunner.runPass(
            on: stack.newBackgroundContext(), includeIntegrityRepairs: true, firstDownloadPending: false,
            orphanGraceLedger: soon.orphanGraceLedger, lastImport: lastImport, now: start.addingTimeInterval(86_400)
        ) { _ in [:] }
        #expect(nextDay.workRowsCleaned == 4) // the fixture's count without any grace
    }
}
