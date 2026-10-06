import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// The restore fixes from the 2026-10-05 hunt (plan "Data model and launch
// repair fixes", Phase 1E), each shown on the restore itself: Close Arrival's
// absences come back as themselves (#10); a restore writes only the private
// store (#32); a replace restore that fails before its save leaves the
// notebook as it was, records and all (#33); the restore updates the copy
// duplicate cleanup keeps (#34); an older backup leaves the attributes it
// predates alone (#35); EventKit's copies are left for the next sync (#36);
// restored notes' student links match their scope (#37); and a backup's
// settings outside the backed-up list aren't applied (#61).

/// What the repair suites share: a context's rows as a backup, and a restore
/// of them from a given format.
@MainActor
private enum Repair {
    static let day = Date(timeIntervalSince1970: 1_790_000_000)

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
            formatVersion: format, encrypted: false, createdAt: day, fileName: "repair", entityCounts: [:]
        )
        _ = try await BackupService().importPayload(
            payload: payload, envelope: envelope, viewContext: context, mode: mode,
            appRouter: AppRouter(), progress: { _, _ in }
        )
    }

    static func all<T: NSManagedObject>(_ type: T.Type, in context: NSManagedObjectContext) throws -> [T] {
        try context.fetch(CDFetchRequest(type))
    }

    /// A context over two in-memory stores carrying the real Private and
    /// Shared configurations, private first as in the app.
    struct TwoStores {
        let context: NSManagedObjectContext
        let privateStore: NSPersistentStore
        let sharedStore: NSPersistentStore
    }

    static func twoStores() throws -> TwoStores {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: try CoreDataStack.sharedModel())
        var stores: [NSPersistentStore] = []
        for configuration in [CoreDataStack.privateConfiguration, CoreDataStack.sharedConfiguration] {
            stores.append(try coordinator.addPersistentStore(
                type: .inMemory, configuration: configuration,
                at: URL(fileURLWithPath: "/dev/null").appendingPathComponent(configuration)
            ))
        }
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return TwoStores(context: context, privateStore: stores[0], sharedStore: stores[1])
    }

    /// "<id> <first name>" for each student in `store`, sorted.
    static func students(in store: NSPersistentStore, of context: NSManagedObjectContext) throws -> [String] {
        let request = CDFetchRequest(CDStudent.self)
        request.affectedStores = [store]
        return try context.fetch(request).map { "\($0.id?.uuidString ?? "?") \($0.firstName)" }.sorted()
    }

    /// The students the note `id` links to, sorted.
    static func linkedStudents(of id: UUID, in context: NSManagedObjectContext) throws -> [String] {
        let note = try #require(try all(CDNote.self, in: context).first { $0.id == id })
        let links = note.studentLinks?.allObjects as? [CDNoteStudentLink] ?? []
        return links.filter { !$0.isDeleted }.map(\.studentID).sorted()
    }
}

@Suite("Restore repairs (2026-10-05): what a restore writes", .serialized)
@MainActor
struct BackupRestoreRepairTests {
    private typealias Restore = BackupRestoreFixtures
    private typealias Fixtures = BackupStreamingFixtures

    private struct Boom: Error {}

    // MARK: - #10 Close Arrival's absences

    @Test("An automatic absence from Close Arrival round-trips as stored, in both modes")
    func closeArrivalAbsenceRoundTrips() async throws {
        let source = try CoreDataTestHelpers.makeContext()
        let automatic = CoreDataTestHelpers.seedAttendance(in: source, date: Repair.day)
        automatic.statusRaw = AttendanceStatus.absent.rawValue
        automatic.absenceReasonRaw = AttendanceDeduplication.automaticAbsenceRaw
        let sick = CoreDataTestHelpers.seedAttendance(in: source, date: Repair.day)
        sick.statusRaw = AttendanceStatus.absent.rawValue
        sick.absenceReasonRaw = AbsenceReason.sick.rawValue
        let present = CoreDataTestHelpers.seedAttendance(in: source, date: Repair.day)
        present.statusRaw = AttendanceStatus.present.rawValue
        try source.save()

        let automaticID = try #require(automatic.id)
        let sickID = try #require(sick.id)
        let presentID = try #require(present.id)
        let payload = Repair.payload(of: source)
        let exported = Dictionary(uniqueKeysWithValues: payload.attendance.map { ($0.id, $0.absenceReason ?? "-") })
        #expect(exported[automaticID] == "closeArrival")
        #expect(exported[sickID] == "sick")
        #expect(exported[presentID] == "-", "no reason is left out, as before")

        let fresh = try CoreDataTestHelpers.makeContext()
        try await Repair.restore(payload, into: fresh, mode: .replace)
        let rows = try Repair.all(CDAttendanceRecord.self, in: fresh)
        let restored = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.absenceReasonRaw) })
        #expect(restored[automatic.id] == "closeArrival")
        #expect(restored[sick.id] == "sick")
        #expect(restored[present.id] == "none")

        // Merge over the same record marked otherwise since.
        automatic.absenceReasonRaw = AbsenceReason.vacation.rawValue
        try source.save()
        try await Repair.restore(payload, into: source, mode: .merge)
        #expect(automatic.absenceReasonRaw == "closeArrival")
    }

    // MARK: - #32 Only the private store

    @Test("A restore neither updates nor clears a classroom in the shared store; its records go private")
    func restoreTouchesOnlyThePrivateStore() async throws {
        let sharedID = UUID()
        let othersID = UUID()
        let ownID = UUID()
        let source = try CoreDataTestHelpers.makeContext()
        CoreDataTestHelpers.seedStudent(in: source, firstName: "Ours").id = sharedID
        CoreDataTestHelpers.seedStudent(in: source, firstName: "Own").id = ownID
        try source.save()
        let payload = Repair.payload(of: source)

        for mode in [BackupService.RestoreMode.merge, .replace] {
            let stores = try Repair.twoStores()
            let context = stores.context
            for (id, name) in [(sharedID, "Theirs"), (othersID, "Other")] {
                let accepted = CoreDataTestHelpers.seedStudent(in: context, firstName: name)
                accepted.id = id
                context.assign(accepted, to: stores.sharedStore)
            }
            try context.save()
            let sharedBefore = try Repair.students(in: stores.sharedStore, of: context)

            try await Repair.restore(payload, into: context, mode: mode)

            let sharedAfter = try Repair.students(in: stores.sharedStore, of: context)
            #expect(sharedAfter == sharedBefore, "\(mode): shared store untouched")
            let expected = ["\(sharedID.uuidString) Ours", "\(ownID.uuidString) Own"].sorted()
            let privateAfter = try Repair.students(in: stores.privateStore, of: context)
            #expect(privateAfter == expected, "\(mode): the backup in the private store")
        }
    }

    // MARK: - #33 A failed replace

    @Test("A replace restore failing before its save leaves every record as it was, the same objects")
    func failedReplaceLeavesTheNotebook() async throws {
        let (store, url) = try await Restore.makeBackup(bulk: 0)
        defer { store.remove() }
        let target = try CoreDataTestHelpers.makeInMemoryStack()
        let context = target.viewContext
        _ = try await Restore.restore(url, into: context, mode: .merge)
        let before = try Restore.snapshot(of: context)
        let objectsBefore = Set(try Repair.all(CDStudent.self, in: context).map(\.objectID))
            .union(try Repair.all(CDNote.self, in: context).map(\.objectID))

        let once = Fixtures.FirstTime()
        let recorder = Restore.recorder(failure: { phase in
            phase == "import WorkModel" && once.claim() ? Boom() : nil
        })
        await #expect(throws: Boom.self) {
            _ = try await BackupPipelineRecorder.$current.withValue(recorder) {
                try await BackupImporter.restore(
                    from: url, into: context, mode: .replace, appRouter: AppRouter(), progress: { _, _ in }
                )
            }
        }

        #expect(!context.hasChanges)
        context.refreshAllObjects()
        #expect(try Restore.snapshot(of: context) == before, "nothing cleared")
        let objectsAfter = Set(try Repair.all(CDStudent.self, in: context).map(\.objectID))
            .union(try Repair.all(CDNote.self, in: context).map(\.objectID))
        #expect(objectsAfter == objectsBefore, "no record deleted and added again")
    }

    @Test("A restore failing before it starts keeps the guide's unsaved edits, on the same records")
    func failedRestoreKeepsUnsavedEdits() async throws {
        let (store, url) = try await Restore.makeBackup(bulk: 0)
        defer { store.remove() }
        let source = try Fixtures.contents(of: url)
        let damaged = store.archiveURL("Damaged")
        try Restore.writeArchive(
            source.paths.filter { $0 != "manifest.json" }.map { ($0, source.bodies[$0] ?? Data()) }, to: damaged
        )
        let target = try CoreDataTestHelpers.makeInMemoryStack()
        let context = target.viewContext
        _ = try await Restore.restore(url, into: context, mode: .merge)
        let student = try #require(try Repair.all(CDStudent.self, in: context).first)
        student.firstName = "Edited, not saved"

        let coordinator = BackupCoordinator(
            backupService: BackupService(), transactionManager: BackupTransactionManager(), appRouter: AppRouter()
        )
        var checkpoint: URL?
        do {
            _ = try await coordinator.importBackup(viewContext: context, from: damaged, mode: .replace) { _, _ in }
            Issue.record("The restore should have failed")
        } catch BackupTransactionManager.TransactionError.importFailed(_, let checkpointURL) {
            checkpoint = checkpointURL
        }
        if let checkpoint { try? FileManager.default.removeItem(at: checkpoint) }

        #expect(checkpoint == nil, "nothing to go back to")
        #expect(context.hasChanges, "the edit is still unsaved")
        #expect(!student.isDeleted && student.managedObjectContext === context)
        #expect(student.firstName == "Edited, not saved")
    }

    // MARK: - #34 Duplicates

    @Test("Of two copies with one id, the restore finds the one duplicate cleanup keeps", arguments: [true, false])
    func duplicatesResolveToTheKeeper(keeperFirst: Bool) throws {
        // On disk, each copy saved on its own, so unsorted fetches return them
        // in the order they were saved; an id map that kept the last one it
        // read found the keeper in at most one of the two orders.
        let store = try Fixtures.makeStore()
        defer { store.remove() }
        let context = store.context
        let id = UUID()
        var copies: [String: CDNote] = [:]
        for body in keeperFirst ? ["Keeper", "Copy"] : ["Copy", "Keeper"] {
            let note = CoreDataTestHelpers.seedNote(in: context, body: body)
            note.id = id
            // Cleanup keeps the earliest made.
            note.createdAt = Date(timeIntervalSince1970: body == "Keeper" ? 1_780_000_000 : 1_780_086_400)
            try context.save()
            copies[body] = note
        }
        let keeper = try #require(copies["Keeper"])

        let index = BackupEntityIndex(context: context)
        #expect(try index.existing(CDNote.self, id: id)?.objectID == keeper.objectID)
        #expect(try index.related(CDNote.self, id: id)?.objectID == keeper.objectID)
    }
}

@Suite("Restore repairs (2026-10-05): what a restore keeps", .serialized)
@MainActor
struct BackupRestoreKeepsTests {

    // MARK: - #35 Older formats

    @Test("A backup older than an attribute leaves the record's own value; a current one clears it")
    func olderBackupKeepsAttributesItPredates() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let record = CoreDataTestHelpers.seedAttendance(in: context, date: Repair.day)
        record.statusRaw = AttendanceStatus.leftEarly.rawValue
        record.note = "Grandma picks up at noon"
        record.recordedByName = "Ms. Ana"
        record.markedAt = Repair.day
        record.leavesAt = Repair.day.addingTimeInterval(3_600)
        record.leftAt = Repair.day.addingTimeInterval(3_700)
        record.statusBeforeLeavingRaw = AttendanceStatus.present.rawValue
        let need = CDOrderItem(context: context)
        need.title = "Glue"
        need.supplyID = UUID().uuidString
        need.addedByID = "assistant-1"
        let note = CoreDataTestHelpers.seedNote(in: context, body: "For the report")
        note.includeInReport = true
        try context.save()

        // The same records as a v28 backup has them: none of the later fields
        // (and, here, no marker's name, which v28 does carry).
        var old = Repair.payload(of: context)
        var row = try #require(old.attendance.first)
        row.status = AttendanceStatus.absent.rawValue
        (row.note, row.recordedBy, row.recordedByID, row.recordedByName) = (nil, nil, nil, nil)
        (row.markedAt, row.leftAt, row.leavesAt, row.returnedAt) = (nil, nil, nil, nil)
        row.statusBeforeLeavingRaw = nil
        old.attendance = [row]
        var needRow = try #require(old.orderItems?.first)
        needRow.values["title"] = .string("Glue sticks")
        for key in ["supplyID", "addedByID", "sourceRaw", "addedByName"] { needRow.values[key] = nil }
        old.orderItems = [needRow]
        var noteRow = try #require(old.notes.first)
        noteRow.body = "For the report, edited"
        noteRow.includeInReport = nil
        old.notes = [noteRow]
        let supplyID = need.supplyID

        try await Repair.restore(old, format: 28, into: context, mode: .merge)
        #expect(record.statusRaw == AttendanceStatus.absent.rawValue, "the row was restored")
        #expect(record.note == "Grandma picks up at noon")
        #expect(record.recordedByName == nil, "v28 carries who marked it, so a row without one means no one")
        #expect(record.markedAt == Repair.day)
        #expect(record.leavesAt == Repair.day.addingTimeInterval(3_600))
        #expect(record.leftAt == Repair.day.addingTimeInterval(3_700))
        #expect(record.statusBeforeLeavingRaw == AttendanceStatus.present.rawValue)
        #expect(need.title == "Glue sticks", "the row was restored")
        #expect(need.supplyID == supplyID)
        #expect(need.addedByID == "assistant-1")
        #expect(note.body == "For the report, edited", "the row was restored")
        #expect(note.includeInReport)

        // A current backup's row without a note means the day has none.
        try await Repair.restore(old, into: context, mode: .merge)
        #expect(record.note == nil)
        #expect(record.leavesAt == nil)
        #expect(need.supplyID == nil)
    }

    // MARK: - #36 EventKit's copies

    @Test("Reminders and events aren't restored: the device's copies stay, and the next sync adds nothing")
    func eventKitCopiesAreLeftForTheNextSync() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let data = MirrorFixture.reminder("ek-1", modified: MirrorFixture.firstSync)
        let reminder = EventKitMirror.insertReminder(data, listID: "list", in: context, now: MirrorFixture.firstSync)
        let event = EventKitMirror.insertEvent(
            MirrorFixture.event("ev-1"), calendarID: "cal-school", in: context, now: MirrorFixture.firstSync
        )
        let note = CoreDataTestHelpers.seedNote(in: context, body: "About the paint order")
        note.reminder = reminder
        try context.save()

        var payload = Repair.payload(of: context)
        payload.reminders = (payload.reminders ?? []) + [ReminderDTO(
            id: UUID(), title: "From another device", notes: nil, dueDate: nil, isCompleted: false,
            completedAt: nil, createdAt: Repair.day, updatedAt: Repair.day
        )]

        try await Repair.restore(payload, into: context, mode: .replace)

        #expect(try Repair.all(CDReminder.self, in: context).map(\.objectID) == [reminder.objectID])
        #expect(reminder.eventKitReminderID == "ek-1")
        #expect(try Repair.all(CDCalendarEvent.self, in: context).map(\.objectID) == [event.objectID])
        #expect(event.eventKitEventID == "ev-1")
        let restoredNote = try #require(try Repair.all(CDNote.self, in: context).first)
        #expect(restoredNote.reminder?.objectID == reminder.objectID, "the note still points at it")

        let next = EventKitMirror.reconcileReminders([data], listID: "list", in: context, now: MirrorFixture.secondSync)
        #expect(next == EventKitMirror.Outcome())
        #expect(try Repair.all(CDReminder.self, in: context).count == 1)
    }

    // MARK: - #37 Student links

    @Test("A restored note's student links are the students its scope names")
    func restoredNotesLinkTheirScope() async throws {
        let (before, after) = (UUID(), UUID())
        let noteID = UUID()
        let source = try CoreDataTestHelpers.makeContext()
        let backedUp = CoreDataTestHelpers.seedNote(in: source, body: "Both at the bead cabinet")
        backedUp.id = noteID
        backedUp.scope = .students([after])
        backedUp.syncStudentLinks(in: source)
        try source.save()
        let payload = Repair.payload(of: source)
        var withoutLinks = payload
        withoutLinks.noteStudentLinks = []

        for (situation, rows) in [("with its links", payload), ("from a backup without links", withoutLinks)] {
            let context = try CoreDataTestHelpers.makeContext()
            let local = CoreDataTestHelpers.seedNote(in: context, body: "Before")
            local.id = noteID
            local.scope = .students([before])
            local.syncStudentLinks(in: context)
            try context.save()

            try await Repair.restore(rows, into: context, mode: .merge)
            #expect(try Repair.linkedStudents(of: noteID, in: context) == [after.uuidString], "\(situation)")
            #expect(!context.hasChanges, "\(situation): saved")
        }
    }

    // MARK: - #61 Settings

    @Test("A setting outside the backed-up list isn't applied by a restore")
    func unlistedSettingIsNotApplied() {
        let key = "BackupRestoreKeepsTests.notBackedUp.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        BackupPreferencesService.applyPreferencesDTO(PreferencesDTO(values: [key: .bool(true)]))
        #expect(UserDefaults.standard.object(forKey: key) == nil)
    }
}
