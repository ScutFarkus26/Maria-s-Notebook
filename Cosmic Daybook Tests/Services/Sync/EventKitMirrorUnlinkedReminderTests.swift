import Foundation
@preconcurrency import CoreData
import Testing
@testable import CosmicDaybook

// Simplify the app, Phase 9: a reminder row a restore brought back without
// its Apple Reminders link (backups leave the links out) is taken over by the
// next sync, rather than getting a linked copy inserted beside it. Links stay
// per device; nothing is matched across devices.

/// Rows and lists the take-over suites share.
@MainActor
enum UnlinkedReminderFixture {

    private typealias Fixture = MirrorFixture

    static let otherDue = DateComponents(
        calendar: Calendar(identifier: .gregorian),
        timeZone: TimeZone(identifier: "America/New_York"),
        year: 2026, month: 10, day: 2, hour: 9
    )

    /// A reminder made at `firstSync`, as the copies `copy` makes are: a restored copy keeps its creation date.
    static func reminder(
        _ id: String, title: String = "Order paint", notes: String? = nil, due: DateComponents? = nil,
        completed: Bool = false, completedAt: Date? = nil, created: Date? = Fixture.firstSync, modified: Date?
    ) -> ReminderSyncData {
        Fixture.reminder(
            id, title: title, notes: notes, due: due, completed: completed, completedAt: completedAt,
            created: created, modified: modified
        )
    }

    static let list = [
        UnlinkedReminderFixture.reminder("r1", due: Fixture.dueSoon, modified: Fixture.firstSync),
        UnlinkedReminderFixture.reminder("r2", title: "Call Ms. Levin", notes: "About Friday", modified: Fixture.firstSync),
        UnlinkedReminderFixture.reminder(
            "r3", title: "Field trip forms", completed: true, completedAt: Fixture.firstSync,
            created: Fixture.firstSync, modified: Fixture.firstSync
        )
    ]

    static func rows(in context: NSManagedObjectContext) -> [CDReminder] {
        context.safeFetch(CDFetchRequest(CDReminder.self))
    }

    /// A row with no link, as a restore leaves one.
    @discardableResult
    static func copy(
        _ title: String, due: DateComponents? = nil, completed: Bool = false, created: Date? = nil,
        in context: NSManagedObjectContext
    ) -> CDReminder {
        let row = CDReminder(context: context)
        row.title = title
        row.dueDate = due?.date
        row.isCompleted = completed
        row.createdAt = created ?? Fixture.firstSync
        return row
    }

    /// The reminder rows as a restore by a build before 2026-10-05 wrote
    /// them: the backup's records (dates in whole seconds), with no links.
    static func restoreAsOlderBuildsDid(
        _ rows: [CDReminder], into context: NSManagedObjectContext
    ) throws -> [ReminderDTO] {
        let encoded = try BackupWriter.ndjsonEncoder().encode(BackupDTOTransformers.toDTOs(rows))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let dtos = try decoder.decode([ReminderDTO].self, from: encoded)
        BackupEntityImporter.importReminders(dtos, into: context, existing: { _ in nil })
        return dtos
    }
}

/// A restore, then a sync: one row per reminder.
@Suite("EventKit mirrors: a restore, then a sync")
@MainActor
struct EventKitMirrorRestoreThenSyncTests {

    private typealias Fixture = MirrorFixture
    private typealias Shared = UnlinkedReminderFixture

    @Test("A restore by an older build, then a sync, leaves one row per reminder, notes kept")
    func olderRestoreThenSync() throws {
        let synced = try CoreDataTestHelpers.makeContext()
        EventKitMirror.reconcileReminders(Shared.list, listID: "list", in: synced, now: Fixture.firstSync)
        #expect(synced.safeSave())

        // The notebook as the restore left it, with a note on "Call Ms. Levin".
        let context = try CoreDataTestHelpers.makeContext()
        let dtos = try Shared.restoreAsOlderBuildsDid(Shared.rows(in: synced), into: context)
        let call = try #require(Shared.rows(in: context).first { $0.title == "Call Ms. Levin" })
        CoreDataTestHelpers.seedNote(in: context, body: "Ask about the bus").reminder = call
        #expect(context.safeSave())
        #expect(Shared.rows(in: context).allSatisfy { $0.eventKitReminderID == nil })

        let outcome = EventKitMirror.reconcileReminders(
            Shared.list, listID: "list", in: context, now: Fixture.secondSync
        )
        #expect(outcome == EventKitMirror.Outcome(updated: 3))
        #expect(context.safeSave())

        let rows = Shared.rows(in: context)
        #expect(rows.count == 3)
        #expect(Set(rows.compactMap(\.id)) == Set(dtos.map(\.id)))
        #expect(Set(rows.compactMap(\.eventKitReminderID)) == ["r1", "r2", "r3"])
        #expect(rows.allSatisfy { $0.eventKitCalendarID == "list" && $0.lastSyncedAt == Fixture.secondSync })
        #expect(call.eventKitReminderID == "r2")
        #expect(call.noteItems?.count == 1)
        #expect(NotebookJunkCleanup.duplicateReminders(in: context).isEmpty)

        // From then on the rows are this device's own, and an unchanged list writes nothing.
        let next = EventKitMirror.reconcileReminders(Shared.list, listID: "list", in: context, now: Fixture.thirdSync)
        #expect(next == EventKitMirror.Outcome())
        #expect(!context.hasChanges)
    }

    @Test("A restore today leaves reminder rows alone, and the next sync keeps one row each")
    func currentRestoreThenSync() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        EventKitMirror.reconcileReminders(Shared.list, listID: "list", in: context, now: Fixture.firstSync)
        let call = try #require(Shared.rows(in: context).first { $0.title == "Call Ms. Levin" })
        CoreDataTestHelpers.seedNote(in: context, body: "Ask about the bus").reminder = call
        #expect(context.safeSave())

        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }
        try await BackupTestUtil.writeCurrentBackup(from: context, to: url)

        // Replace on this device: its rows stay, links and all.
        try await BackupTestUtil.importCurrentBackup(from: url, into: context, mode: .replace)
        #expect(EventKitMirror.reconcileReminders(Shared.list, listID: "list", in: context, now: Fixture.secondSync)
            == EventKitMirror.Outcome())
        let rows = Shared.rows(in: context)
        #expect(rows.count == 3)
        #expect(Set(rows.compactMap(\.eventKitReminderID)) == ["r1", "r2", "r3"])
        let note = try #require(context.safeFetch(CDFetchRequest(CDNote.self)).first)
        #expect(note.reminder?.eventKitReminderID == "r2")

        // A new device: no reminder rows come back, and its first sync adds one each.
        let fresh = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        try await BackupTestUtil.importCurrentBackup(from: url, into: fresh, mode: .merge)
        #expect(Shared.rows(in: fresh).isEmpty)
        let first = EventKitMirror.reconcileReminders(Shared.list, listID: "list", in: fresh, now: Fixture.secondSync)
        #expect(first == EventKitMirror.Outcome(inserted: 3))
        #expect(Shared.rows(in: fresh).count == 3)
    }

}

/// Which unlinked row a reminder takes over, and which it leaves.
@Suite("EventKit mirrors: what counts as an unlinked copy")
@MainActor
struct EventKitMirrorUnlinkedCopyTests {

    private typealias Fixture = MirrorFixture
    private typealias Shared = UnlinkedReminderFixture

    @Test("A reminder with no due date takes only a copy with none; a dated one only its own date")
    func dueDatesMustMatch() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let undated = Shared.copy("Order paint", in: context)
        let dated = Shared.copy("Order paint", due: Fixture.dueSoon, in: context)
        let otherDay = Shared.copy("Order paint", due: Shared.otherDue, in: context)
        #expect(context.safeSave())

        let incoming = [
            UnlinkedReminderFixture.reminder("anytime", modified: Fixture.firstSync),
            UnlinkedReminderFixture.reminder("tuesday", due: Fixture.dueSoon, modified: Fixture.firstSync)
        ]
        let outcome = EventKitMirror.reconcileReminders(incoming, listID: "list", in: context, now: Fixture.secondSync)
        #expect(outcome == EventKitMirror.Outcome(updated: 2))
        #expect(undated.eventKitReminderID == "anytime")
        #expect(dated.eventKitReminderID == "tuesday")
        #expect(otherDay.eventKitReminderID == nil)
        #expect(Shared.rows(in: context).count == 3)
    }

    @Test("Case, accents and spaces don't stop a take-over, and the title then follows Reminders")
    func titleIsFolded() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let shouted = Shared.copy("  ORDER paint ", in: context)
        let accented = Shared.copy("Caf\u{E9} order", in: context)
        let unrelated = Shared.copy("Order paints", in: context)
        #expect(context.safeSave())

        let incoming = [
            UnlinkedReminderFixture.reminder("paint", title: "Order paint", modified: Fixture.firstSync),
            UnlinkedReminderFixture.reminder("cafe", title: "cafe Order", modified: Fixture.firstSync)
        ]
        let outcome = EventKitMirror.reconcileReminders(incoming, listID: "list", in: context, now: Fixture.secondSync)
        #expect(outcome == EventKitMirror.Outcome(updated: 2))
        #expect(shouted.eventKitReminderID == "paint")
        #expect(shouted.title == "Order paint")
        #expect(accented.eventKitReminderID == "cafe")
        #expect(accented.title == "cafe Order")
        #expect(unrelated.eventKitReminderID == nil)
    }

    @Test("A due date the backup cut to the whole second still matches; one a minute off doesn't")
    func dueDateToTheSecond() throws {
        let context = try CoreDataTestHelpers.makeContext()
        var precise = Fixture.dueSoon
        precise.minute = 30
        precise.second = 15
        precise.nanosecond = 400_000_000
        let exact = try #require(precise.date)
        let cut = Shared.copy("Order paint", in: context)
        cut.dueDate = Date(timeIntervalSinceReferenceDate: exact.timeIntervalSinceReferenceDate.rounded(.down))
        let minuteOff = Shared.copy("Order paint", in: context)
        minuteOff.dueDate = exact.addingTimeInterval(60)
        #expect(context.safeSave())

        let incoming = [UnlinkedReminderFixture.reminder("paint", due: precise, modified: Fixture.firstSync)]
        let outcome = EventKitMirror.reconcileReminders(incoming, listID: "list", in: context, now: Fixture.secondSync)
        #expect(outcome == EventKitMirror.Outcome(updated: 1))
        #expect(cut.eventKitReminderID == "paint")
        #expect(cut.dueDate == exact)
        #expect(minuteOff.eventKitReminderID == nil)
    }

    @Test("A copy ticked differently is still taken, and takes Reminders' state")
    func completionStateFollowsReminders() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let open = Shared.copy("Order paint", due: Fixture.dueSoon, in: context)
        #expect(context.safeSave())

        let done = UnlinkedReminderFixture.reminder(
            "paint", due: Fixture.dueSoon, completed: true, completedAt: Fixture.secondSync,
            modified: Fixture.secondSync
        )
        let outcome = EventKitMirror.reconcileReminders([done], listID: "list", in: context, now: Fixture.thirdSync)
        #expect(outcome == EventKitMirror.Outcome(updated: 1))
        #expect(open.eventKitReminderID == "paint")
        #expect(open.isCompleted)
        #expect(open.completedAt == Fixture.secondSync)
        #expect(Shared.rows(in: context).count == 1)
    }

    // MARK: - Several copies

    @Test("Of two copies, one open or done as the reminder is, then one with notes, then the older is taken")
    func copiesAreRanked() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let earlier = Fixture.firstSync.addingTimeInterval(-0.5) // copies of one reminder share its creation date to the second
        // Done in the copy, open in Reminders: passed over for the open one, older or not.
        let doneOlder = Shared.copy("Order paint", completed: true, created: earlier, in: context)
        let openNewer = Shared.copy("Order paint", in: context)
        // Notes win over age.
        let plainOlder = Shared.copy("Call Ms. Levin", created: earlier, in: context)
        let notedNewer = Shared.copy("Call Ms. Levin", in: context)
        CoreDataTestHelpers.seedNote(in: context, body: "Ask about the bus").reminder = notedNewer
        // Otherwise the older.
        let formsOlder = Shared.copy("Field trip forms", created: earlier, in: context)
        let formsNewer = Shared.copy("Field trip forms", in: context)
        #expect(context.safeSave())

        let incoming = [
            UnlinkedReminderFixture.reminder("paint", modified: Fixture.firstSync),
            UnlinkedReminderFixture.reminder("call", title: "Call Ms. Levin", modified: Fixture.firstSync),
            UnlinkedReminderFixture.reminder("forms", title: "Field trip forms", modified: Fixture.firstSync)
        ]
        let outcome = EventKitMirror.reconcileReminders(incoming, listID: "list", in: context, now: Fixture.secondSync)
        #expect(outcome == EventKitMirror.Outcome(updated: 3))
        #expect(openNewer.eventKitReminderID == "paint")
        #expect(notedNewer.eventKitReminderID == "call")
        #expect(formsOlder.eventKitReminderID == "forms")
        #expect(doneOlder.eventKitReminderID == nil)
        #expect(plainOlder.eventKitReminderID == nil)
        #expect(formsNewer.eventKitReminderID == nil)
        #expect(context.safeSave())

        // The copies left are empty doubles of a linked row now, so Settings' clean-up
        // removes the open ones (a done copy of an open reminder isn't grouped with it).
        let leftover = Set(NotebookJunkCleanup.duplicateReminders(in: context).map(\.objectID))
        #expect(leftover == [plainOlder.objectID, formsNewer.objectID])
    }

    @Test("Copies made at the same moment go by id, so every device takes the same one")
    func tiesGoById() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let first = Shared.copy("Order paint", in: context)
        let second = Shared.copy("Order paint", in: context)
        first.id = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")
        second.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")
        #expect(context.safeSave())

        let paint = UnlinkedReminderFixture.reminder("paint", modified: Fixture.firstSync)
        EventKitMirror.reconcileReminders([paint], listID: "list", in: context, now: Fixture.secondSync)
        #expect(second.eventKitReminderID == "paint")
        #expect(first.eventKitReminderID == nil)
    }

    @Test("Two reminders alike take one copy each; a repeated identifier takes only one")
    func eachCopyIsTakenOnce() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let copies = (0..<3).map { _ in Shared.copy("Order paint", due: Fixture.dueSoon, in: context) }
        #expect(context.safeSave())

        let first = UnlinkedReminderFixture.reminder("paint-1", due: Fixture.dueSoon, modified: Fixture.firstSync)
        let second = UnlinkedReminderFixture.reminder("paint-2", due: Fixture.dueSoon, modified: Fixture.firstSync)
        let outcome = EventKitMirror.reconcileReminders(
            [first, second, first], listID: "list", in: context, now: Fixture.secondSync
        )
        #expect(outcome == EventKitMirror.Outcome(updated: 2))
        #expect(copies.compactMap(\.eventKitReminderID).sorted() == ["paint-1", "paint-2"])
        #expect(Shared.rows(in: context).count == 3)
    }

    @Test("A linked row is never taken over, whichever device's link it holds")
    func linkedRowsAreNotCopies() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let iPadRow = EventKitMirror.insertReminder(
            UnlinkedReminderFixture.reminder("ipad-paint", modified: Fixture.firstSync), listID: "ipad-list", in: context,
            now: Fixture.firstSync
        )
        #expect(context.safeSave())

        let outcome = EventKitMirror.reconcileReminders(
            [UnlinkedReminderFixture.reminder("mac-paint", modified: Fixture.firstSync)], listID: "mac-list", in: context,
            now: Fixture.secondSync
        )
        #expect(outcome == EventKitMirror.Outcome(inserted: 1))
        #expect(iPadRow.eventKitReminderID == "ipad-paint")
        #expect(iPadRow.eventKitCalendarID == "ipad-list")
        #expect(iPadRow.lastSyncedAt == Fixture.firstSync)
    }

    @Test("A new reminder with a restored row's title and no due date is not that row; clearing it keeps the old notes")
    func newReminderDoesNotTakeLastYearsRow() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lastYears = Shared.copy("Order paint", created: Fixture.firstSync, in: context)
        CoreDataTestHelpers.seedNote(in: context, body: "Blue, two gallons").reminder = lastYears
        #expect(context.safeSave())

        let created = Fixture.firstSync.addingTimeInterval(365 * 86_400)
        let fresh = Shared.reminder("paint-2027", created: created, modified: created)
        let outcome = EventKitMirror.reconcileReminders([fresh], listID: "list", in: context, now: created)
        #expect(outcome == EventKitMirror.Outcome(inserted: 1))
        #expect(lastYears.eventKitReminderID == nil)
        #expect(Shared.rows(in: context).count == 2)

        // The new reminder is cleared in Reminders: only its own row goes.
        EventKitMirror.reconcileReminders([], listID: "list", in: context, now: created.addingTimeInterval(60))
        #expect(context.safeSave())
        let rows = Shared.rows(in: context)
        #expect(rows.count == 1)
        #expect(rows.first === lastYears)
        #expect(lastYears.noteItems?.count == 1)
    }

    @Test("With no creation date on either side, an undated reminder takes no copy; a dated one still does")
    func missingCreationDate() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let undated = Shared.copy("Order paint", in: context)
        undated.createdAt = nil
        let dated = Shared.copy("Order paint", due: Fixture.dueSoon, in: context)
        dated.createdAt = nil
        #expect(context.safeSave())

        let incoming = [
            Shared.reminder("anytime", created: nil, modified: Fixture.firstSync),
            Shared.reminder("tuesday", due: Fixture.dueSoon, created: nil, modified: Fixture.firstSync)
        ]
        let outcome = EventKitMirror.reconcileReminders(incoming, listID: "list", in: context, now: Fixture.secondSync)
        #expect(outcome == EventKitMirror.Outcome(inserted: 1, updated: 1))
        #expect(undated.eventKitReminderID == nil)
        #expect(dated.eventKitReminderID == "tuesday")
    }

    @Test("A true copy (same creation date) is taken over, and its notes survive later syncs")
    func trueCopyKeepsNotes() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let copy = Shared.copy("Order paint", created: Fixture.firstSync, in: context)
        CoreDataTestHelpers.seedNote(in: context, body: "Blue, two gallons").reminder = copy
        #expect(context.safeSave())

        let paint = Shared.reminder(
            "paint", created: Fixture.firstSync.addingTimeInterval(0.4), modified: Fixture.firstSync
        )
        let outcome = EventKitMirror.reconcileReminders([paint], listID: "list", in: context, now: Fixture.secondSync)
        #expect(outcome == EventKitMirror.Outcome(updated: 1))
        #expect(copy.eventKitReminderID == "paint")
        #expect(Shared.rows(in: context).count == 1)

        EventKitMirror.reconcileReminders([paint], listID: "list", in: context, now: Fixture.thirdSync)
        #expect(context.safeSave())
        #expect(copy.noteItems?.count == 1)
        #expect(Shared.rows(in: context).count == 1)
    }

    @Test("A reminder that already has its row leaves an unlinked copy for the clean-up")
    func existingRowLeavesCopyAlone() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let paint = UnlinkedReminderFixture.reminder("paint", modified: Fixture.firstSync)
        EventKitMirror.reconcileReminders([paint], listID: "list", in: context, now: Fixture.firstSync)
        let leftover = Shared.copy("Order paint", in: context)
        #expect(context.safeSave())

        let outcome = EventKitMirror.reconcileReminders([paint], listID: "list", in: context, now: Fixture.secondSync)
        #expect(outcome == EventKitMirror.Outcome())
        #expect(leftover.eventKitReminderID == nil)
        #expect(NotebookJunkCleanup.duplicateReminders(in: context).map(\.objectID) == [leftover.objectID])
    }
}
