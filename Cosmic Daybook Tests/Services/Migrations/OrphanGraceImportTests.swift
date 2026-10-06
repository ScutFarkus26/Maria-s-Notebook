import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Data model hunt 2026-10-05, #22. The orphan grace counted only time: a
// student missing on two passes a day apart was stripped from every work row
// and lesson, and that synced. A device that had been asleep, offline or
// still importing for that day hadn't heard from iCloud at all, so "missing
// for a day" said nothing about whether she was really gone. The grace now
// also needs a successful import into the store that holds students after
// she was first seen missing; with no import known, the id keeps waiting.

@Suite("The orphan grace waits for an import")
@MainActor
struct OrphanGraceImportTests {
    private typealias Fixture = LaunchRepairFixture
    private let start = Date(timeIntervalSinceReferenceDate: 780_000_000)

    @Test("A day missing is not enough when no import has run since the id went missing")
    func dayAloneIsNotEnough() {
        let first = OrphanStudentGrace(ledger: [:], now: start)
        #expect(first.admit(missing: ["A"], validIDs: []).isEmpty)

        let dayLater = OrphanStudentGrace(ledger: first.ledger, now: start.addingTimeInterval(86_400))
        #expect(dayLater.admit(missing: ["A"], validIDs: []).isEmpty)
        #expect(dayLater.ledger["A"] == start)
    }

    @Test("The launch pass leaves every row alone a day later when no import is known")
    func launchPassWaitsForAnImport() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        try Fixture.seed(stack.viewContext)
        let seeded = Fixture.snapshot(of: stack.viewContext)

        let first = await MigrationRunner.runPass(
            on: stack.newBackgroundContext(), includeIntegrityRepairs: true, firstDownloadPending: false,
            orphanGraceLedger: [:], now: start
        ) { _ in [:] }
        let nextDay = await MigrationRunner.runPass(
            on: stack.newBackgroundContext(), includeIntegrityRepairs: true, firstDownloadPending: false,
            orphanGraceLedger: first.orphanGraceLedger, now: start.addingTimeInterval(86_400)
        ) { _ in [:] }

        #expect(nextDay.workRowsCleaned == 0)
        let result = Fixture.snapshot(of: stack.viewContext)
        #expect(result.workStudents == seeded.workStudents)
        #expect(result.participantStudents == seeded.participantStudents)
        #expect(result.assignmentStudents == seeded.assignmentStudents)
    }

    @Test("With an import since the id went missing, the next day's pass cleans")
    func importSinceLetsThePassClean() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        try Fixture.seed(stack.viewContext)
        let imported = start.addingTimeInterval(600)
        let lastImport: @Sendable (ImportStoreKind) -> Date? = { $0 == .privateStore ? imported : nil }

        let first = await MigrationRunner.runPass(
            on: stack.newBackgroundContext(), includeIntegrityRepairs: true, firstDownloadPending: false,
            orphanGraceLedger: [:], lastImport: lastImport, now: start
        ) { _ in [:] }
        let nextDay = await MigrationRunner.runPass(
            on: stack.newBackgroundContext(), includeIntegrityRepairs: true, firstDownloadPending: false,
            orphanGraceLedger: first.orphanGraceLedger, lastImport: lastImport, now: start.addingTimeInterval(86_400)
        ) { _ in [:] }

        #expect(first.workRowsCleaned == 0)
        #expect(nextDay.workRowsCleaned == 4)
    }

    @Test("On an assistant's notebook only an import into the shared store counts for students")
    func assistantNotebookWaitsForTheSharedStore() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        try Fixture.seed(stack.viewContext)
        CoreDataTestHelpers.seedClassroomMembership(in: stack.viewContext, role: .assistant)
        #expect(CoreDataTestHelpers.save(stack.viewContext))
        let imported = start.addingTimeInterval(600)
        let privateOnly: @Sendable (ImportStoreKind) -> Date? = { $0 == .privateStore ? imported : nil }

        let first = await MigrationRunner.runPass(
            on: stack.newBackgroundContext(), includeIntegrityRepairs: true, firstDownloadPending: false,
            orphanGraceLedger: [:], lastImport: privateOnly, now: start
        ) { _ in [:] }
        let nextDay = await MigrationRunner.runPass(
            on: stack.newBackgroundContext(), includeIntegrityRepairs: true, firstDownloadPending: false,
            orphanGraceLedger: first.orphanGraceLedger, lastImport: privateOnly, now: start.addingTimeInterval(86_400)
        ) { _ in [:] }

        #expect(nextDay.workRowsCleaned == 0)
    }
}
