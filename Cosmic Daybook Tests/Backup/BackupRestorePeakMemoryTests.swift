import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Peak heap and main-thread time during a restore, the one-pass way (every
// entry read, the whole archive decoded, then deduplicated into a second copy
// and imported — kept verbatim in BackupService+LegacyRestore.swift) against
// the app's (`BackupImporter.restore`: decoded as it is read, then imported one
// type at a time from the payload's only copy), on the export measurement's
// store (44,318 rows, 73 types) restored into a fresh in-memory store each run.
// A measurement, not a gate: it runs only on request, alone, because every
// other test in the process allocates too.
//
//   TEST_RUNNER_BACKUP_PEAK_MEMORY=1 nice -n 10 xcodebuild test-without-building … \
//     -only-testing:"Cosmic Daybook Tests/BackupRestorePeakMemoryTests"
//
// The numbers go to the test log as "BackupPeakMemory: …" lines.
@Suite(
    "Backup restore peak memory (on request)",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["BACKUP_PEAK_MEMORY"] != nil)
)
@MainActor
struct BackupRestorePeakMemoryTests {
    private typealias Peak = BackupExportPeakMemoryTests

    /// Main-thread time from "Importing…": to "Syncing to iCloud…", the import
    /// turn (clear, import, save, repair, settings); and to the restore's
    /// return, which adds freeing what it held.
    private final class Stopwatch {
        private var started: ContinuousClock.Instant?
        private(set) var turn: Duration = .zero

        func progress(_ fraction: Double, _ message: String) {
            if message == "Importing\u{2026}" { started = .now }
            if message == "Syncing to iCloud\u{2026}", let started { turn = .now - started }
        }

        func untilNow() -> Duration {
            started.map { .now - $0 } ?? .zero
        }
    }

    private struct Run {
        let rise: Peak.Rise
        let turn: Duration
        let untilReturn: Duration
    }

    /// A restore of a file into a store, reporting progress.
    private typealias RestoreRun = (URL, NSManagedObjectContext, @escaping BackupService.ProgressCallback)
        async throws -> Void

    private static func measure(_ restore: RestoreRun, _ url: URL) async throws -> Run {
        let target = try CoreDataTestHelpers.makeInMemoryStack()
        let watch = Stopwatch()
        var untilReturn: Duration = .zero
        let rise = try await Peak.peakRise {
            try await restore(url, target.viewContext) { watch.progress($0, $1) }
            untilReturn = watch.untilNow()
        }
        return Run(rise: rise, turn: watch.turn, untilReturn: untilReturn)
    }

    private static func onePassRestore(
        _ url: URL, into context: NSManagedObjectContext, progress: @escaping BackupService.ProgressCallback
    ) async throws {
        let archive = try await BackupImporter.legacyDecodeArchive(at: url)
        _ = try await BackupImporter.legacyImportDecoded(
            archive, from: url, into: context, mode: .merge, appRouter: AppRouter(), progress: progress
        )
    }

    private static func appRestore(
        _ url: URL, into context: NSManagedObjectContext, progress: @escaping BackupService.ProgressCallback
    ) async throws {
        _ = try await BackupImporter.restore(
            from: url, into: context, mode: .merge, appRouter: AppRouter(), progress: progress
        )
    }

    private static func milliseconds(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        return String(format: "%.0f ms", Double(seconds) * 1_000 + Double(attoseconds) / 1e15)
    }

    private static func report(_ name: String, _ runs: [Run]) {
        let rises = runs.map(\.rise.overall).sorted()
        let turns = runs.map(\.turn).sorted()
        let returns = runs.map(\.untilReturn).sorted()
        print("BackupPeakMemory: \(name) restore rise \(Peak.describe(runs.map(\.rise)))")
        print("BackupPeakMemory: \(name) restore median \(Peak.megabytes(rises[3])) "
            + "(best \(Peak.megabytes(rises[0])), worst \(Peak.megabytes(rises[5]))); "
            + "import turn median \(milliseconds(turns[3])) \(turns.map(milliseconds)); "
            + "until return median \(milliseconds(returns[3])) \(returns.map(milliseconds))")
    }

    @Test("Peak heap and main-thread time: one-pass restore vs the app's")
    func measureRestore() async throws {
        let store = try BackupStreamingFixtures.makeStore()
        defer { store.remove() }
        try BackupStreamingFixtures.seedEveryType(in: store.context, bulk: 12_000)
        try Peak.seedPresentations(in: store.context, count: 8_000)
        let url = store.archiveURL("Source")
        try await BackupRestoreFixtures.writeBackup(of: store.context, to: url)

        var onePass: [Run] = []
        var app: [Run] = []
        for round in 0..<6 {
            // Alternate which goes first, so neither always inherits the other's leftovers.
            if round.isMultiple(of: 2) {
                app.append(try await Self.measure(Self.appRestore, url))
                onePass.append(try await Self.measure(Self.onePassRestore, url))
            } else {
                onePass.append(try await Self.measure(Self.onePassRestore, url))
                app.append(try await Self.measure(Self.appRestore, url))
            }
        }
        Self.report("one-pass", onePass)
        Self.report("app", app)
        #expect(app.map(\.rise.overall).sorted()[3] < onePass.map(\.rise.overall).sorted()[3])
    }

    /// A Replace over a notebook that already holds everything: since
    /// 2026-10-05 its clear and its import go into one save, so the deletes
    /// and the inserts are held together (2026-10-05 review). Measured, not
    /// gated, like the restore above; the numbers say whether a full notebook
    /// can still be replaced on an iPhone.
    @Test("Peak heap and main-thread time: Replace over a full notebook")
    func measureReplaceOverFullStore() async throws {
        let store = try BackupStreamingFixtures.makeStore()
        defer { store.remove() }
        try BackupStreamingFixtures.seedEveryType(in: store.context, bulk: 12_000)
        try Peak.seedPresentations(in: store.context, count: 8_000)
        let url = store.archiveURL("Source")
        try await BackupRestoreFixtures.writeBackup(of: store.context, to: url)

        var runs: [Run] = []
        for _ in 0..<6 {
            let target = try CoreDataTestHelpers.makeInMemoryStack()
            _ = try await BackupImporter.restore(
                from: url, into: target.viewContext, mode: .merge, appRouter: AppRouter(), progress: { _, _ in }
            )
            let watch = Stopwatch()
            var untilReturn: Duration = .zero
            let rise = try await Peak.peakRise {
                _ = try await BackupImporter.restore(
                    from: url, into: target.viewContext, mode: .replace, appRouter: AppRouter(),
                    progress: { watch.progress($0, $1) }
                )
                untilReturn = watch.untilNow()
            }
            runs.append(Run(rise: rise, turn: watch.turn, untilReturn: untilReturn))
        }
        Self.report("replace over full", runs)
        #expect(runs.count == 6)
    }
}
