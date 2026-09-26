#if os(iOS)
import BackgroundTasks
#endif
import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// DANNY DECIDED (2026-09-25): the iPad's overnight BGProcessingTask backup
// waits for a charger, and when iPadOS ends the task early the export stops
// between record types instead of finishing a long write. Pinned here: a
// stopped export leaves nothing at its destination, not even the hidden
// temp file; every other export still runs to the end when its task is
// cancelled; the task's completion handler fires exactly once; and a
// stopped run does not start the scene-phase gap.
@Suite("Background backup stops cleanly")
@MainActor
struct BackgroundBackupStopTests {

    private static func seededContext() throws -> NSManagedObjectContext {
        let context = try CoreDataTestHelpers.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Lovelace")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Grace", lastName: "Hopper")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Golden Beads")
        CoreDataTestHelpers.seedNote(in: context, body: "Ada built the thousand cube")
        CoreDataTestHelpers.seedNote(in: context, body: "Grace wants the bank game")
        CoreDataTestHelpers.seedWorkModel(
            in: context, title: "Bead chain", studentID: ada.id ?? UUID(), lessonID: lesson.id ?? UUID()
        )
        try context.save()
        return context
    }

    private static func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackgroundBackupStop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func archiveURL(in directory: URL) -> URL {
        directory.appendingPathComponent("AutoBackup").appendingPathExtension(BackupFile.fileExtension)
    }

    /// A recorder that cancels the export's own task when it reaches `phase`,
    /// the way the expiration handler cancels the background task mid-write.
    private static func cancelling(at phase: String) -> BackupPipelineRecorder {
        BackupPipelineRecorder { reached in
            if reached == phase {
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
    }

    /// Runs the export in a task of its own, so cancelling it never cancels
    /// the test.
    private static func export(
        _ context: NSManagedObjectContext,
        to url: URL,
        stopsWhenCancelled: Bool,
        recorder: BackupPipelineRecorder,
        cancelBeforeStart: Bool = false
    ) async -> Result<BackupOperationSummary, any Error> {
        let export = Task { @MainActor in
            try await BackupPipelineRecorder.$current.withValue(recorder) {
                try await BackupWriter.write(viewContext: context, to: url, stopsWhenCancelled: stopsWhenCancelled)
            }
        }
        if cancelBeforeStart { export.cancel() }
        return await export.result
    }

    private static func contents(of directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
    }

    // MARK: - Stopping the export

    @Test("An expired background export stops at the next record type and leaves no file")
    func expiredExportLeavesNothing() async throws {
        let context = try Self.seededContext()
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = Self.archiveURL(in: directory)
        let recorder = Self.cancelling(at: "encode Student")

        let result = await Self.export(context, to: url, stopsWhenCancelled: true, recorder: recorder)

        #expect(throws: CancellationError.self) { try result.get() }
        let phases = recorder.reached.map(\.phase)
        #expect(phases.contains("encode Student"))
        #expect(!phases.contains("encode Lesson"), "the next record type was never encoded: \(phases)")
        #expect(!phases.contains("verify"))
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try Self.contents(of: directory).isEmpty, "the hidden .partial file is removed too")
    }

    @Test("A background export already ended before it began collects nothing")
    func expiredBeforeStartCollectsNothing() async throws {
        let context = try Self.seededContext()
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = BackupPipelineRecorder()

        let result = await Self.export(
            context, to: Self.archiveURL(in: directory), stopsWhenCancelled: true,
            recorder: recorder, cancelBeforeStart: true
        )

        #expect(throws: CancellationError.self) { try result.get() }
        #expect(recorder.reached.isEmpty)
        #expect(try Self.contents(of: directory).isEmpty)
    }

    @Test("Every other export (manual, quit, scene-phase, scheduled) still finishes when its task is cancelled")
    func otherExportsRunToTheEnd() async throws {
        let context = try Self.seededContext()
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = Self.archiveURL(in: directory)
        let recorder = Self.cancelling(at: "encode Student")

        let result = await Self.export(context, to: url, stopsWhenCancelled: false, recorder: recorder)

        let summary = try result.get()
        #expect(summary.entityCounts["Student"] == 2)
        #expect(recorder.reached.last?.phase == "verify")
        #expect(try Self.contents(of: directory) == [url.lastPathComponent])
        let archive = try await BackupImporter.decodeArchive(at: url)
        #expect(archive.payload.notes.count == 2)
    }

    // MARK: - The scene-phase gap

    @Test("A run the system stopped early does not start the gap; a finished or failed one does")
    func stoppedRunDoesNotStartTheGap() {
        let now = Date()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AutoBackup.mtbbackup")
        #expect(AutoBackupManager.startsBackgroundGap(.success(now, url)))
        #expect(AutoBackupManager.startsBackgroundGap(.failure(now, CocoaError(.fileWriteOutOfSpace))))
        #expect(!AutoBackupManager.startsBackgroundGap(.failure(now, CancellationError())))
        #expect(!AutoBackupManager.startsBackgroundGap(.skippedNoChanges(now)))
    }
}

#if os(iOS)
// The BGProcessingTask's completion. `setTaskCompleted` must be called exactly
// once, whichever of the work and the expiration handler gets there first.
@Suite("Background backup task completion")
@MainActor
struct BackgroundBackupTaskCompletionTests {

    private final class Log {
        var completions: [Bool] = []
        var workStarted = false
        var workSawCancellation: Bool?
    }

    private func waitUntil(timeout: Duration = .seconds(30), _ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    @Test("The overnight request waits for a charger")
    func requestRequiresExternalPower() {
        let twelveHours: TimeInterval = 43_200
        let elevenHours: TimeInterval = 39_600
        let request = BackupBackgroundTaskManager.makeRequest(after: twelveHours)
        #expect(request.identifier == BackupBackgroundTaskManager.taskIdentifier)
        #expect(request.requiresExternalPower)
        #expect(!request.requiresNetworkConnectivity)
        let lead: TimeInterval = request.earliestBeginDate?.timeIntervalSinceNow ?? 0
        #expect(lead > elevenHours)
    }

    @Test("Work that finishes reports success once; a late expiration adds nothing")
    func finishedWorkCompletesOnce() async {
        let log = Log()
        let expire = BackupBackgroundTaskManager.startWork(
            { log.workStarted = true },
            complete: { log.completions.append($0) }
        )

        #expect(await waitUntil { !log.completions.isEmpty })
        expire()
        #expect(log.completions == [true])
        #expect(log.workStarted)
    }

    @Test("Expiration reports failure once, cancels the work, and the work's own finish adds nothing")
    func expirationCompletesOnceAndCancels() async {
        let log = Log()
        let expire = BackupBackgroundTaskManager.startWork({
            log.workStarted = true
            // Stands in for the export: runs until its task is cancelled.
            let deadline = ContinuousClock.now + .seconds(30)
            while !Task.isCancelled, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(5))
            }
            log.workSawCancellation = Task.isCancelled
        }, complete: { log.completions.append($0) })

        #expect(await waitUntil { log.workStarted })
        expire()
        #expect(log.completions == [false])
        #expect(await waitUntil { log.workSawCancellation != nil })
        #expect(log.workSawCancellation == true)
        #expect(log.completions == [false])
    }

    @Test("The completion gate lets exactly one of many concurrent callers through")
    func gateAdmitsOneCaller() async {
        for _ in 0..<50 {
            let gate = CompletionGate()
            let winners = await withTaskGroup(of: Bool.self) { group in
                for _ in 0..<32 {
                    group.addTask { gate.claim() }
                }
                var count = 0
                for await won in group where won {
                    count += 1
                }
                return count
            }
            #expect(winners == 1)
        }
    }
}
#endif
