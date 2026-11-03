import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-11-02 (sync, sharing, Core Data, migrations and backups),
// the restore's findings: a Merge put every record the backup held back to
// the backup's version (#1); the Merge preview counted 15 types (#22); and
// the iCloud wait subscribed after the save (#23). The Replace findings
// (#2, #10) and the project sessions (#7) are in `+Replace`.

/// Restoring a hand-built payload, as the 10-29 tests do.
@MainActor
enum Fix1102 {
    static func at(_ seconds: Double) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + seconds) }

    /// Everything in `context` as one backup's rows, with no settings.
    static func payload(of context: NSManagedObjectContext) -> BackupPayload {
        var payload = BackupService().collectPayload(viewContext: context)
        payload.preferences = PreferencesDTO(values: [:])
        return payload
    }

    static func restore(
        _ payload: BackupPayload,
        format: Int = BackupWriter.formatVersion,
        into context: NSManagedObjectContext,
        mode: BackupService.RestoreMode
    ) async throws {
        let envelope = BackupEnvelope(
            formatVersion: format, encrypted: false, createdAt: at(0), fileName: "fix1102", entityCounts: [:]
        )
        _ = try await BackupService().importPayload(
            payload: payload, envelope: envelope, viewContext: context, mode: mode,
            appRouter: AppRouter(), progress: { _, _ in }
        )
    }

    static func analyze(
        _ digest: BackupPreviewDigest,
        against context: NSManagedObjectContext,
        mode: BackupService.RestoreMode
    ) -> BackupPreviewAnalyzer.AnalysisResult {
        let index = EntityIDIndexCache(context: context)
        return BackupPreviewAnalyzer.analyze(
            digest: digest, viewContext: context, mode: mode,
            formatVersion: BackupWriter.formatVersion, entityExists: { index.exists($0, id: $1) }
        )
    }

    /// The preview's key for a backed-up type ("WorkParticipantEntity" → "WorkParticipant").
    static func key(_ entity: BackupEntity) -> String {
        BackupPlainNames.normalized(String(describing: entity.managedType()))
    }

    static func students(in context: NSManagedObjectContext) -> [UUID: String] {
        Dictionary(uniqueKeysWithValues: context.safeFetch(CDFetchRequest(CDStudent.self)).compactMap { student in
            student.id.map { ($0, student.firstName) }
        })
    }
}

@Suite("Restore fixes (2026-11-02): a Merge keeps what changed since the backup", .serialized)
@MainActor
struct BackupMergeNewerWinsTests {

    /// A notebook and a backup of it, then changes on each side. Ada was
    /// renamed here since the backup; Bea's backup row is newer than her
    /// record (this device is behind); Cy's record has no date; Dee's
    /// dates are equal; the project's backup row has no date; Eve is only
    /// in the backup.
    private struct Scenario {
        let context: NSManagedObjectContext
        let backup: BackupPayload
        let ids: [String: UUID]
    }

    private static func notebookAndBackup() throws -> Scenario {
        let context = try CoreDataTestHelpers.makeContext()
        var ids: [String: UUID] = [:]
        for name in ["Ada", "Bea", "Cy", "Dee"] {
            let student = CoreDataTestHelpers.seedStudent(in: context, firstName: name, lastName: "Here")
            student.setValue(Fix1102.at(10), forKey: "modifiedAt")
            ids[name] = student.id
        }
        let project = CDProject(context: context)
        project.title = "Here"
        project.modifiedAt = Fix1102.at(10)
        ids["Project"] = project.id
        try context.save()

        var backup = Fix1102.payload(of: context)
        func edit(_ name: String, _ change: (inout StudentDTO) -> Void) throws {
            let index = try #require(backup.students.firstIndex { $0.id == ids[name] })
            change(&backup.students[index])
        }
        try edit("Ada") { $0.firstName = "Ada (backup)" }
        try edit("Bea") { $0.firstName = "Bea (backup)"; $0.modifiedAt = Fix1102.at(50) }
        try edit("Cy") { $0.firstName = "Cy (backup)" }
        try edit("Dee") { $0.firstName = "Dee (backup)" }
        var eve = backup.students[0]
        eve.id = UUID()
        eve.firstName = "Eve"
        backup.students.append(eve)
        ids["Eve"] = eve.id
        backup.projects[0].title = "Backup title"
        backup.projects[0].modifiedAt = nil

        // Since the backup, on this device.
        let stored = context.safeFetch(CDFetchRequest(CDStudent.self))
        let ada = try #require(stored.first { $0.id == ids["Ada"] })
        ada.firstName = "Ada (since)"
        ada.setValue(Fix1102.at(50), forKey: "modifiedAt")
        let cyrus = try #require(stored.first { $0.id == ids["Cy"] })
        cyrus.firstName = "Cy (here)"
        cyrus.setValue(nil, forKey: "modifiedAt")
        project.title = "Here (since)"
        project.modifiedAt = Fix1102.at(50)
        try context.save()
        return Scenario(context: context, backup: backup, ids: ids)
    }

    @Test("A Merge leaves a record changed since the backup and takes the backup's row for the rest")
    func mergeKeepsNewerRecords() async throws {
        let scenario = try Self.notebookAndBackup()
        let (context, backup, ids) = (scenario.context, scenario.backup, scenario.ids)

        let preview = Fix1102.analyze(BackupPreviewDigest(payload: backup), against: context, mode: .merge)
        #expect(preview.inserts["Student"] == 1, "Eve")
        #expect(preview.skips["Student"] == 3, "Bea, Cy and Dee take the backup's version")
        #expect(preview.kept["Student"] == 1, "Ada is kept")
        #expect(preview.skips["Project"] == 1, "a backup row with no date is taken")

        try await Fix1102.restore(backup, into: context, mode: .merge)
        let names = Fix1102.students(in: context)
        #expect(names[try #require(ids["Ada"])] == "Ada (since)", "changed since the backup: kept")
        #expect(names[try #require(ids["Bea"])] == "Bea (backup)", "older here: the backup's")
        #expect(names[try #require(ids["Cy"])] == "Cy (backup)", "no date here: the backup's")
        #expect(names[try #require(ids["Dee"])] == "Dee (backup)", "the same date: the backup's")
        #expect(names[try #require(ids["Eve"])] == "Eve", "new: added")
        let project = try #require(context.safeFetch(CDFetchRequest(CDProject.self)).first)
        #expect(project.title == "Backup title", "no date in the backup: the backup's")
    }

    @Test("A Replace still takes every row the backup holds")
    func replaceTakesTheBackup() async throws {
        let scenario = try Self.notebookAndBackup()
        let (context, ids) = (scenario.context, scenario.ids)
        try await Fix1102.restore(scenario.backup, into: context, mode: .replace)
        let names = Fix1102.students(in: context)
        #expect(names[try #require(ids["Ada"])] == "Ada (backup)")
        #expect(names.count == 5)
    }

    @Test("Every type whose records have a change date hands it to the restore; the rest have none")
    func everyDatedTypeReportsItsDate() throws {
        let context = try CoreDataTestHelpers.makeContext()
        try BackupFieldCoverageTests.seedEveryBackedUpEntity(into: context)
        try context.save()
        let payload = Fix1102.payload(of: context)
        let model = try #require(context.persistentStoreCoordinator?.managedObjectModel)
        var dated = 0
        var undated = 0
        for entity in BackupEntityTable.entities {
            guard let rows = entity.rowsIn(payload), !rows.isEmpty,
                  let name = BackupFetchHelper.entityName(for: entity.managedType(), in: context) else { continue }
            let modelEntity = try #require(model.entitiesByName[name])
            if BackupMergeRule.changeDateAttribute(of: modelEntity) != nil {
                dated += 1
                #expect(rows.allSatisfy { $0.rowModifiedAt != nil }, "\(entity.name): its change date reaches a Merge")
            } else {
                undated += 1
                #expect(rows.allSatisfy { $0.rowModifiedAt == nil }, "\(entity.name) has no change date")
            }
            if BackupMergeRule.completionAttribute(of: modelEntity) == nil {
                #expect(rows.allSatisfy { $0.rowCompletedAt == nil }, "\(entity.name) isn't judged by when it was done")
            }
        }
        #expect(dated >= 20, "\(dated) dated types checked")
        #expect(dated + undated >= 70, "\(dated + undated) types checked")
    }

    @Test("The Merge preview counts every backed-up type")
    func mergePreviewCountsEveryType() throws {
        let source = try CoreDataTestHelpers.makeContext()
        try BackupFieldCoverageTests.seedEveryBackedUpEntity(into: source)
        try source.save()
        let digest = BackupPreviewDigest(payload: Fix1102.payload(of: source))
        let empty = try CoreDataTestHelpers.makeContext()
        let fresh = Fix1102.analyze(digest, against: empty, mode: .merge)
        let same = Fix1102.analyze(digest, against: source, mode: .merge)
        var counted = 0
        for entity in BackupEntityTable.entities {
            let key = Fix1102.key(entity)
            let rows = digest.stamps(entity.name).count
            guard rows > 0, !BackupEntityRegistry.keptOnRestoreEntityNames.contains(key),
                  !BackupEntityRegistry.notYetBackedUpEntityNames.contains(String(describing: entity.managedType()))
            else { continue }
            counted += 1
            #expect(fresh.inserts[key] == rows, "\(key): every row new to an empty notebook")
            #expect(same.inserts[key] == 0, "\(key): nothing new to the notebook that made the backup")
            #expect((same.skips[key] ?? 0) + (same.kept[key] ?? 0) == rows, "\(key): every row already here")
        }
        #expect(counted >= 70, "\(counted) types counted")
    }
}

/// Every wait here is bounded by the timeout it passes, so a listener that
/// hears nothing fails the test after a few seconds instead of hanging it.
@Suite("Restore fixes (2026-11-02): the iCloud wait hears an export that ends at once", .timeLimit(.minutes(1)))
@MainActor
struct BackupCloudExportWaitTests {
    private static let exportFinished = Notification.Name("BackupCloudExportWaitTests.exportFinished")

    /// When the restore saved, in these tests; an export's start is posted
    /// as seconds from it (`started`), the restore's own at 0 by default.
    private static let savedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// A listener on a center of its own that reads each post with `result`,
    /// as an export that started `started` seconds after the save.
    private static func listener(
        on center: NotificationCenter,
        result: @escaping @Sendable (Notification) -> CloudExportWaitResult?
    ) -> CloudExportListener {
        let savedAt = Self.savedAt
        return CloudExportListener.listening(on: center, to: exportFinished, waits: true) { note in
            result(note).map { finished in
                let started = note.userInfo?["started"] as? TimeInterval ?? 0
                return CloudExportListener.Export(startedAt: savedAt.addingTimeInterval(started), result: finished)
            }
        }
    }

    private static func wait(for listener: CloudExportListener, timeout: Duration) async -> CloudExportWaitResult {
        await BackupService().awaitCloudKitExport(listener, startedFrom: savedAt, timeout: timeout)
    }

    @Test("An export that finishes during the save, before the wait begins, is heard")
    func hearsAnExportBeforeTheWait() async {
        let center = NotificationCenter()
        let listener = Self.listener(on: center) { _ in .completed }
        defer { listener.stop() }

        // The quick export, posted off the main actor (as CloudKit posts) while the save runs.
        let name = Self.exportFinished
        await Task.detached { center.post(name: name, object: nil) }.value

        let result = await Self.wait(for: listener, timeout: .seconds(5))
        guard case .completed = result else {
            Issue.record("the export before the wait was missed: \(result)")
            return
        }
    }

    @Test("A failed export is passed on, after the events that aren't finished exports")
    func passesOnAFailedExport() async {
        let center = NotificationCenter()
        let listener = Self.listener(on: center) { note in
            (note.userInfo?["failed"] as? String).map { .failed(reason: $0) }
        }
        defer { listener.stop() }

        center.post(name: Self.exportFinished, object: nil)
        center.post(name: Self.exportFinished, object: nil, userInfo: ["failed": "quota"])

        let result = await Self.wait(for: listener, timeout: .seconds(5))
        guard case .failed(let reason) = result else {
            Issue.record("expected the failure, got \(result)")
            return
        }
        #expect(reason == "quota")
    }

    @Test("An export that started before the restore's save isn't the restore's, however late it finishes")
    func skipsAnExportStartedBeforeTheSave() async {
        let center = NotificationCenter()
        let listener = Self.listener(on: center) { note in
            (note.userInfo?["failed"] as? String).map { CloudExportWaitResult.failed(reason: $0) } ?? .completed
        }
        defer { listener.stop() }

        // The edits saved just before the restore went up from a second
        // before its save, and finish during it; then the restore's own.
        let name = Self.exportFinished
        await Task.detached { center.post(name: name, object: nil, userInfo: ["started": -1.0]) }.value
        center.post(name: Self.exportFinished, object: nil, userInfo: ["started": 0.5, "failed": "the restore's"])

        let result = await Self.wait(for: listener, timeout: .seconds(5))
        guard case .failed(let reason) = result else {
            Issue.record("expected the restore's own export, got \(result)")
            return
        }
        #expect(reason == "the restore's")
    }

    @Test("With only an export that started before the save, the wait ends at its timeout")
    func waitsPastAnEarlierExport() async {
        let center = NotificationCenter()
        let listener = Self.listener(on: center) { _ in .completed }
        defer { listener.stop() }

        center.post(name: Self.exportFinished, object: nil, userInfo: ["started": -0.001])

        let result = await Self.wait(for: listener, timeout: .milliseconds(200))
        guard case .timedOut = result else {
            Issue.record("an export from before the save was taken: \(result)")
            return
        }
    }

    @Test("With no finished export, the wait ends at its timeout")
    func timesOutWithoutAnExport() async {
        let center = NotificationCenter()
        let listener = Self.listener(on: center) { _ in nil }
        defer { listener.stop() }

        center.post(name: Self.exportFinished, object: nil)

        let result = await Self.wait(for: listener, timeout: .milliseconds(200))
        guard case .timedOut = result else {
            Issue.record("expected a timeout, got \(result)")
            return
        }
    }

    @Test("A stopped listener hears nothing more")
    func stoppedListenerHearsNothing() async {
        let center = NotificationCenter()
        let listener = Self.listener(on: center) { _ in .completed }
        listener.stop()

        center.post(name: Self.exportFinished, object: nil)

        let result = await Self.wait(for: listener, timeout: .seconds(5))
        guard case .timedOut = result else {
            Issue.record("expected nothing heard after stop, got \(result)")
            return
        }
    }

    @Test("A restore into a notebook that doesn't sync waits for nothing")
    func noWaitWithoutICloud() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let service = BackupService()
        let listener = service.cloudExportListener(for: context)
        defer { listener.stop() }
        #expect(!listener.waits)
        let result = await service.awaitCloudKitExport(listener, startedFrom: Date(), timeout: .seconds(30))
        guard case .completed = result else {
            Issue.record("expected no wait, got \(result)")
            return
        }
    }
}
