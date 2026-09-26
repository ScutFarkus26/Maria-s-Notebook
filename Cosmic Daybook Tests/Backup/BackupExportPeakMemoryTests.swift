import CoreData
import Darwin
import Foundation
import Synchronization
import Testing
@testable import CosmicDaybook

// Peak heap during an export, the one-pass way (the old collector's whole
// payload, then `encodeAndWrite`) against the streamed way (`write`), and
// during a restore preview, the whole-payload way (decode everything, then the
// old analyzer) against the digest (`previewImport`), on one store. A
// measurement, not a gate: it runs only on request, alone, because every other
// test in the process allocates too.
//
//   TEST_RUNNER_BACKUP_PEAK_MEMORY=1 nice -n 10 xcodebuild test-without-building … \
//     -only-testing:"Cosmic Daybook Tests/BackupExportPeakMemoryTests"
//
// The numbers go to the test log as "BackupPeakMemory: …" lines.
@Suite(
    "Backup export peak memory (on request)",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["BACKUP_PEAK_MEMORY"] != nil)
)
@MainActor
struct BackupExportPeakMemoryTests {

    /// Samples malloc's bytes-in-use every half millisecond on its own thread
    /// and keeps the highest reading in each pipeline phase.
    nonisolated final class PeakSampler: Sendable {
        private let state = Mutex((running: true, phase: "start", peaks: [String: Int]()))

        static func bytesInUse() -> Int {
            var stats = malloc_statistics_t()
            malloc_zone_statistics(nil, &stats)
            return Int(stats.size_in_use)
        }

        func start() {
            Thread.detachNewThread { [self] in
                while state.withLock({ $0.running }) {
                    let now = Self.bytesInUse()
                    state.withLock { $0.peaks[$0.phase] = max($0.peaks[$0.phase] ?? 0, now) }
                    usleep(500)
                }
            }
        }

        func reached(_ phase: String) {
            // "encode Student", "encode Note", … are one phase here.
            let group = phase.hasPrefix("encode ") ? "encode" : phase
            state.withLock { $0.phase = group }
        }

        func stop() -> [String: Int] {
            state.withLock { state in
                state.running = false
                return state.peaks
            }
        }
    }

    /// How far the heap rose above where it started, overall and per phase.
    struct Rise {
        let overall: Int
        let byPhase: [String: Int]
    }

    private static func peakRise(_ work: () async throws -> Void) async throws -> Rise {
        let baseline = PeakSampler.bytesInUse()
        let sampler = PeakSampler()
        let recorder = BackupPipelineRecorder { sampler.reached($0) }
        sampler.start()
        try await BackupPipelineRecorder.$current.withValue(recorder) {
            try await work()
        }
        let byPhase = sampler.stop().mapValues { max(0, $0 - baseline) }
        return Rise(overall: byPhase.values.max() ?? 0, byPhase: byPhase)
    }

    private static func describe(_ rises: [Rise]) -> String {
        rises.map { rise in
            let phases = rise.byPhase.sorted { $0.key < $1.key }.map { "\($0.key) \(megabytes($0.value))" }
            return "\(megabytes(rise.overall)) [\(phases.joined(separator: ", "))]"
        }.joined(separator: "; ")
    }

    private static func megabytes(_ bytes: Int) -> String {
        String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }

    @Test("Peak heap: one-pass export vs streamed export")
    func measurePeakHeap() async throws {
        let store = try BackupStreamingFixtures.makeStore()
        defer { store.remove() }
        try BackupStreamingFixtures.seedEveryType(in: store.context, bulk: 12_000)
        try Self.seedPresentations(in: store.context, count: 8_000)
        let context = store.context

        // What the two paths hold at their peaks, counted.
        let payload = BackupService().legacyCollectPayload(viewContext: context)
        let entries = try BackupWriter.serializeEntries(from: payload)
        let rows = entries.reduce(0) { $0 + $1.count }
        let ndjson = entries.reduce(0) { $0 + $1.ndjson.count }
        let largest = try #require(entries.max { $0.ndjson.count < $1.ndjson.count })
        let packed = try entries.reduce(0) { total, entry in
            total + (try autoreleasepool { try (entry.ndjson as NSData).compressed(using: .lz4) as Data }).count
        }
        print("BackupPeakMemory: \(rows) rows in \(entries.count) types; NDJSON \(Self.megabytes(ndjson)); "
            + "largest type \(largest.entityName): \(largest.count) rows, \(Self.megabytes(largest.ndjson.count)); "
            + "all types LZ4-packed \(Self.megabytes(packed))")

        var onePass: [Rise] = []
        var streamed: [Rise] = []
        for round in 0..<6 {
            let streamedURL = store.archiveURL("Streamed-\(round)")
            let streamedRun = {
                streamed.append(try await Self.peakRise {
                    _ = try await BackupWriter.write(viewContext: context, to: streamedURL)
                })
            }
            let onePassURL = store.archiveURL("OnePass-\(round)")
            let onePassRun = {
                onePass.append(try await Self.peakRise {
                    BackupPipelineProbe.reach("collect")
                    let whole = BackupService().legacyCollectPayload(viewContext: context)
                    _ = try await BackupWriter.encodeAndWrite(
                        payload: whole, deviceName: "Measure", to: onePassURL, progress: { _, _ in }
                    )
                })
            }
            // Alternate which goes first, so neither always inherits the other's leftovers.
            if round.isMultiple(of: 2) {
                try await streamedRun()
                try await onePassRun()
            } else {
                try await onePassRun()
                try await streamedRun()
            }
        }
        let onePassRises = onePass.map(\.overall).sorted()
        let streamedRises = streamed.map(\.overall).sorted()
        print("BackupPeakMemory: one-pass rise \(Self.describe(onePass))")
        print("BackupPeakMemory: streamed rise \(Self.describe(streamed))")
        print("BackupPeakMemory: median \(Self.megabytes(onePassRises[3])) -> \(Self.megabytes(streamedRises[3])); "
            + "best \(Self.megabytes(onePassRises[0])) -> \(Self.megabytes(streamedRises[0]))")
        #expect(streamedRises[3] < onePassRises[3])
    }

    @Test("Peak heap: whole-payload restore preview vs digest preview", arguments: [1_000, 12_000])
    func measurePreviewPeakHeap(bulk: Int) async throws {
        let store = try BackupStreamingFixtures.makeStore()
        defer { store.remove() }
        try BackupStreamingFixtures.seedEveryType(in: store.context, bulk: bulk)
        try Self.seedPresentations(in: store.context, count: bulk * 2 / 3)
        let context = store.context
        let url = store.archiveURL("Source")
        _ = try await BackupWriter.write(viewContext: context, to: url)
        let coordinator = BackupCoordinator(
            backupService: BackupService(), transactionManager: BackupTransactionManager(), appRouter: AppRouter()
        )

        var whole: [Rise] = []
        var digest: [Rise] = []
        for round in 0..<6 {
            let wholeRun = {
                whole.append(try await Self.peakRise {
                    let archive = try await BackupImporter.decodeArchive(at: url)
                    let index = EntityIDIndexCache(context: context)
                    _ = LegacyBackupPreviewAnalyzer.analyze(
                        payload: archive.payload, viewContext: context, mode: .merge,
                        entityExists: { index.exists($0, id: $1) }
                    )
                })
            }
            let digestRun = {
                digest.append(try await Self.peakRise {
                    _ = try await coordinator.previewImport(
                        viewContext: context, from: url, mode: .merge, progress: { _, _ in }
                    )
                })
            }
            if round.isMultiple(of: 2) {
                try await wholeRun()
                try await digestRun()
            } else {
                try await digestRun()
                try await wholeRun()
            }
        }
        let wholeRises = whole.map(\.overall).sorted()
        let digestRises = digest.map(\.overall).sorted()
        print("BackupPeakMemory: [bulk \(bulk)] whole-payload preview rise \(Self.describe(whole))")
        print("BackupPeakMemory: [bulk \(bulk)] digest preview rise \(Self.describe(digest))")
        print("BackupPeakMemory: [bulk \(bulk)] preview median \(Self.megabytes(wholeRises[3])) -> "
            + "\(Self.megabytes(digestRises[3])); best \(Self.megabytes(wholeRises[0])) -> "
            + "\(Self.megabytes(digestRises[0]))")
        // On a small store the archive reader's own buffers (~27 MB, both
        // paths) dwarf the records, and the two are within noise.
        if bulk >= 10_000 {
            #expect(digestRises[3] < wholeRises[3])
        }
    }

    /// Lesson presentations: a fourth large type, with the long rows real
    /// notebooks have.
    private static func seedPresentations(in context: NSManagedObjectContext, count: Int) throws {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        for index in 0..<count {
            let presentation = NSEntityDescription.insertNewObject(forEntityName: "LessonPresentation", into: context)
            for (name, attribute) in presentation.entity.attributesByName {
                switch attribute.attributeType {
                case .UUIDAttributeType:
                    presentation.setValue(UUID(), forKey: name)
                case .dateAttributeType:
                    presentation.setValue(start.addingTimeInterval(Double(index) * 900), forKey: name)
                case .stringAttributeType:
                    presentation.setValue(name.hasSuffix("ID") ? UUID().uuidString : "\(name) \(index)", forKey: name)
                default:
                    continue
                }
            }
        }
        try context.save()
    }
}
