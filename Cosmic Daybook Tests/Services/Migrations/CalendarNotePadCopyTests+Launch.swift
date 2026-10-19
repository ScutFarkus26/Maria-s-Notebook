import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The rest of `CalendarNotePadCopyTests`: notes with nothing to copy, which
/// store the pads land in, the launch step itself, what the Calendar shows
/// meanwhile, and Today's 30-day cleanup.
extension CalendarNotePadCopyTests {

    // MARK: - Nothing to copy

    @Test("Empty and blank notes make no pad, and a note on a day that doesn't exist stays where it is, unmarked")
    func emptyAndImpossibleNotes() throws {
        let context = try CoreDataTestHelpers.makeContext()
        note("", on: fieldTrip, in: context)
        let blank = note("  \n\t", on: pictureDay, in: context)
        let impossible = note("Leap day party", on: CellID(year: 2026, month: 2, day: 30), in: context)
        #expect(CoreDataTestHelpers.save(context))
        let stamp = impossible.modifiedAt

        // The empty note isn't even read; the blank one and 30 February are passed over.
        #expect(CalendarNotePadCopy.run(in: context) == CalendarNotePadCopy.Outcome(skipped: 2))
        #expect(!context.hasChanges)
        #expect(context.safeFetch(CDFetchRequest(CDDayPad.self)).isEmpty)
        // 30 February isn't rolled into March.
        #expect(try pads(on: CellID(year: 2026, month: 3, day: 2), in: context).isEmpty)
        #expect(!impossible.isDeleted)
        // Neither is marked: nothing of theirs is in a pad.
        #expect(impossible.modifiedAt == stamp)
        #expect(!CalendarNotePadCopy.isCopied(impossible))
        #expect(!CalendarNotePadCopy.isCopied(blank))
        #expect(CalendarNotePadCopy.run(in: context) == CalendarNotePadCopy.Outcome(skipped: 2))
    }

    // MARK: - Where it writes

    @Test("The pads go to the guide's private store, never the classroom share, and the marks are read from SQLite")
    func writesToThePrivateStore() throws {
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        note("Field trip to the zoo", on: fieldTrip, in: context)
        // A note saved with no stamp at all is waiting too; one already marked isn't.
        note("Picture day", on: pictureDay, in: context).modifiedAt = nil
        marked(note("Bring forms", on: CellID(year: 2026, month: 10, day: 22), in: context))
        #expect(CoreDataTestHelpers.save(context))

        // The store's own query leaves the marked note out.
        let waiting = CDFetchRequest(CDCalendarNote.self)
        waiting.predicate = CalendarNotePadCopy.notCopiedPredicate()
        let reader = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        reader.persistentStoreCoordinator = context.persistentStoreCoordinator
        #expect(Set(reader.safeFetch(waiting).map(\.text)) == ["Field trip to the zoo", "Picture day"])

        #expect(copy(context) == CalendarNotePadCopy.Outcome(copied: 2))
        let written = try #require(try pads(on: fieldTrip, in: context).first)
        #expect(written.objectID.persistentStore?.configurationName == CoreDataStack.privateConfiguration)
        #expect(try pads(on: CellID(year: 2026, month: 10, day: 22), in: context).isEmpty)
        reader.reset()
        #expect(reader.safeFetch(waiting).isEmpty)
    }

    // MARK: - The launch step

    @Test("The launch step waits out the first download, then saves the pad and the note's mark together")
    func launchStep() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let trip = note("Field trip to the zoo", on: fieldTrip, in: context)
        #expect(CoreDataTestHelpers.save(context))
        let step = { (pending: Bool) in
            MigrationRunner.copyCalendarNotesToPads(in: context, firstDownloadPending: pending)
        }
        let reader = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        reader.persistentStoreCoordinator = context.persistentStoreCoordinator
        let stored = { try #require(try reader.existingObject(with: trip.objectID) as? CDCalendarNote) }

        #expect(step(true) == nil)
        #expect(context.safeFetch(CDFetchRequest(CDDayPad.self)).isEmpty)
        #expect(!CalendarNotePadCopy.isCopied(try stored()))

        #expect(step(false) == CalendarNotePadCopy.Outcome(copied: 1))
        #expect(!context.hasChanges)
        // Both in the store, from the one save.
        reader.reset()
        #expect(reader.safeFetch(CDFetchRequest(CDDayPad.self)).map(\.body) == ["Field trip to the zoo"])
        #expect(CalendarNotePadCopy.isCopied(try stored()))

        // Nothing new, nothing written.
        #expect(step(false) == CalendarNotePadCopy.Outcome())
        #expect(!context.hasChanges)
    }

    @Test("The launch step never saves a change someone else has on screen: it waits until the context is clean")
    func skipsWhileTheContextHasAnUnsavedEdit() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let trip = note("Field trip to the zoo", on: fieldTrip, in: context)
        let typing = try pad("Call Maya's", on: pictureDay, in: context)
        #expect(CoreDataTestHelpers.save(context))
        // She is part way through a word on another day, not saved yet.
        typing.setBody("Call Maya's da")
        let reader = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        reader.persistentStoreCoordinator = context.persistentStoreCoordinator

        #expect(MigrationRunner.copyCalendarNotesToPads(in: context, firstDownloadPending: false) == nil)
        // Nothing copied, nothing saved, her edit still hers to save.
        #expect(try pads(on: fieldTrip, in: context).isEmpty)
        #expect(!CalendarNotePadCopy.isCopied(trip))
        #expect(context.hasChanges)
        #expect(typing.body == "Call Maya's da")
        let storedTyping = try #require(try reader.existingObject(with: typing.objectID) as? CDDayPad)
        #expect(storedTyping.body == "Call Maya's")

        // Once her editor saves, the next try copies.
        #expect(CoreDataTestHelpers.save(context))
        #expect(MigrationRunner.copyCalendarNotesToPads(in: context, firstDownloadPending: false)
            == CalendarNotePadCopy.Outcome(copied: 1))
        #expect(try body(on: fieldTrip, in: context) == "Field trip to the zoo")
        #expect(try body(on: pictureDay, in: context) == "Call Maya's da")
    }

    // MARK: - Waiting for iCloud

    @Test("This launch counts as caught up only once an import that began after it started has finished")
    func caughtUpRule() {
        let launch = Date(timeIntervalSince1970: 1_780_000_000)
        #expect(!CalendarNotePadCopy.caughtUp(lastImport: nil, launchedAt: launch))
        #expect(!CalendarNotePadCopy.caughtUp(lastImport: launch.addingTimeInterval(-1), launchedAt: launch))
        #expect(CalendarNotePadCopy.caughtUp(lastImport: launch, launchedAt: launch))
        #expect(CalendarNotePadCopy.caughtUp(lastImport: launch.addingTimeInterval(30), launchedAt: launch))
    }

    @Test("Before this launch's import from iCloud has finished, the launch step copies nothing")
    func waitsForThisLaunchsImport() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let trip = note("Field trip to the zoo", on: fieldTrip, in: context)
        #expect(CoreDataTestHelpers.save(context))
        let launch = Date(timeIntervalSince1970: 1_780_000_000)

        // The last import on record is a previous launch's; the only one that
        // finishes now began before this launch too, and then iCloud goes quiet.
        let (stale, staleImports) = AsyncStream.makeStream(of: Date.self)
        staleImports.yield(launch.addingTimeInterval(-5))
        staleImports.finish()
        let waited = await MigrationRunner.copyCalendarNotesToPadsOnceCaughtUp(
            in: context, launchedAt: launch, lastImport: launch.addingTimeInterval(-3600),
            finishedImports: stale
        )
        #expect(waited == nil)
        #expect(context.safeFetch(CDFetchRequest(CDDayPad.self)).isEmpty)
        #expect(!CalendarNotePadCopy.isCopied(trip))

        // An import that began after the launch finishes: now it copies, once.
        let (fresh, freshImports) = AsyncStream.makeStream(of: Date.self)
        freshImports.yield(launch.addingTimeInterval(-5))
        freshImports.yield(launch.addingTimeInterval(2))
        freshImports.yield(launch.addingTimeInterval(60))
        freshImports.finish()
        let copied = await MigrationRunner.copyCalendarNotesToPadsOnceCaughtUp(
            in: context, launchedAt: launch, lastImport: nil, finishedImports: fresh
        )
        #expect(copied == CalendarNotePadCopy.Outcome(copied: 1))
        #expect(try body(on: fieldTrip, in: context) == "Field trip to the zoo")
    }

    @Test("A launch already caught up (or with iCloud sync off) copies without waiting")
    func copiesAtOnceWhenCaughtUp() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        note("Field trip to the zoo", on: fieldTrip, in: context)
        #expect(CoreDataTestHelpers.save(context))
        let launch = Date(timeIntervalSince1970: 1_780_000_000)
        // A stream that never ends: waiting on it would hang the test.
        let (never, continuation) = AsyncStream.makeStream(of: Date.self)
        defer { continuation.finish() }

        let outcome = await MigrationRunner.copyCalendarNotesToPadsOnceCaughtUp(
            in: context, launchedAt: launch, lastImport: launch.addingTimeInterval(10),
            finishedImports: never
        )
        #expect(outcome == CalendarNotePadCopy.Outcome(copied: 1))
    }

    @Test("A launch caught up while a change on screen is unsaved tries again at each finished import, until it can")
    func retriesAtTheNextImportWhenTheContextIsDirty() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        note("Field trip to the zoo", on: fieldTrip, in: context)
        let typing = try pad("Call Maya's", on: pictureDay, in: context)
        #expect(CoreDataTestHelpers.save(context))
        typing.setBody("Call Maya's da")
        let launch = Date(timeIntervalSince1970: 1_780_000_000)

        // Imports finish after the launch: during the first she's still typing;
        // before the second her editor saves. A third taken would mean the
        // copy kept waiting after it had run.
        let script = ImportScript(
            starts: [20, 40, 60].map { launch.addingTimeInterval($0) }, savingBefore: 2, in: context
        )
        let imports = AsyncStream<Date>(unfolding: { await script.next() })

        let outcome = await MigrationRunner.copyCalendarNotesToPadsOnceCaughtUp(
            in: context, launchedAt: launch, lastImport: launch.addingTimeInterval(1), finishedImports: imports
        )
        #expect(outcome == CalendarNotePadCopy.Outcome(copied: 1))
        #expect(script.taken == 2)
        // At each import, before her save: the change still unsaved, and no
        // pad for the field trip yet (only the one she's typing in).
        let typingOnly = ImportScript.Look(unsaved: true, pads: 1)
        #expect(script.seen == [typingOnly, typingOnly])
        #expect(script.saved == true)
        #expect(try body(on: fieldTrip, in: context) == "Field trip to the zoo")
        #expect(typing.body == "Call Maya's da")
        #expect(!context.hasChanges)
    }

    // MARK: - Shown until copied

    @Test("Until the Mac copies it, a note shows beside its day's pad; one marked, or already in the pad, doesn't")
    func uncopiedNotesShow() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let inPad = CellID(year: 2026, month: 10, day: 20)
        let formsDay = CellID(year: 2026, month: 10, day: 22)
        let editedOff = CellID(year: 2026, month: 10, day: 23)
        try pad("Morning: picture DAY, 9:00", on: inPad, in: context)
        try pad("PEACE assembly", on: formsDay, in: context)
        try pad("Photos moved", on: editedOff, in: context)
        note("Picture day", on: inPad, in: context)
        let sharedID = UUID()
        note("Bring forms", on: formsDay, id: sharedID, in: context)
        note("Bring  forms", on: formsDay, id: sharedID, made: 60, in: context)
        note("PE", on: formsDay, made: 120, in: context)
        // Copied, then she took the line off the pad.
        let handled = marked(note("Field trip", on: editedOff, in: context))
        note("Not at school", on: pictureDay, in: context)
        #expect(CoreDataTestHelpers.save(context))

        // What the Calendar fetches leaves the marked note out...
        let waiting = CDFetchRequest(CDCalendarNote.self)
        waiting.predicate = CalendarNotePadCopy.notCopiedPredicate()
        let fetched = context.safeFetch(waiting)
        #expect(!fetched.contains(handled))
        #expect(fetched.count == 5)
        // ...and the lookup skips it even when handed every note.
        let padTexts = CalendarNoteEditor.padTexts(of: context.safeFetch(CDFetchRequest(CDDayPad.self)))
        let expected: [CellID: [String]] = [formsDay: ["Bring forms", "PE"], pictureDay: ["Not at school"]]
        #expect(CalendarNotePadCopy.uncopiedTexts(of: fetched, padTexts: padTexts) == expected)
        let every = context.safeFetch(CDFetchRequest(CDCalendarNote.self))
        #expect(every.contains(handled))
        #expect(CalendarNotePadCopy.uncopiedTexts(of: every, padTexts: padTexts) == expected)

        // Un-marked (an older build edits it), it shows again.
        handled.modifiedAt = Date()
        #expect(CalendarNotePadCopy.uncopiedTexts(of: [handled], padText: "Photos moved") == ["Field trip"])
    }

    // MARK: - The 30-day cleanup

    @Test("Today's 30-day cleanup keeps a pad holding a calendar note's text, past or future")
    func retentionKeepsCopiedPads() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let now = try #require(
            AppCalendar.shared.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 15))
        )
        let longAgo = CellID(date: AppCalendar.addingDays(-60, to: now))
        let nextWeek = CellID(date: AppCalendar.addingDays(7, to: now))
        note("Back to school night", on: longAgo, in: context)
        note("Conferences", on: nextWeek, in: context)
        // A control: an empty pad as old as the first, which the cleanup does take.
        let emptyOld = try pad("", on: CellID(date: AppCalendar.addingDays(-61, to: now)), in: context)
        let emptyFuture = try pad("", on: CellID(date: AppCalendar.addingDays(8, to: now)), in: context)
        #expect(CoreDataTestHelpers.save(context))
        #expect(copy(context) == CalendarNotePadCopy.Outcome(copied: 2))
        let kept = Set(context.safeFetch(CDFetchRequest(CDDayPad.self)).compactMap(\.id))

        let outcome = await TodayRetentionCleanup.run(
            on: LaunchRepairFixture.backgroundContext(beside: context), now: now
        )

        let reader = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        reader.persistentStoreCoordinator = context.persistentStoreCoordinator
        let remaining = reader.safeFetch(CDFetchRequest(CDDayPad.self))
        #expect(outcome.dayPads == 1)
        #expect(Set(remaining.compactMap(\.id)) == kept.subtracting([try #require(emptyOld.id)]))
        #expect(remaining.contains { $0.body == "Back to school night" })
        #expect(remaining.contains { $0.body == "Conferences" })
        #expect(remaining.contains { $0.id == emptyFuture.id })
    }
}

/// Finished imports for `copyCalendarNotesToPadsOnceCaughtUp`, one at a time,
/// noting what `context` holds as each is handed over, and saving it (her
/// editor's save) just before the import numbered `savingBefore`.
@MainActor
final class ImportScript {
    private let context: NSManagedObjectContext
    private var starts: [Date]
    private let savingBefore: Int
    /// How many imports the copy has taken.
    private(set) var taken = 0
    /// What the context held as an import was taken, before any save.
    struct Look: Equatable {
        /// A change not saved yet.
        let unsaved: Bool
        /// How many day pads.
        let pads: Int
    }

    /// At each import taken.
    private(set) var seen: [Look] = []
    /// Whether her save went through; nil until it is made.
    private(set) var saved: Bool?

    init(starts: [Date], savingBefore: Int, in context: NSManagedObjectContext) {
        self.starts = starts
        self.savingBefore = savingBefore
        self.context = context
    }

    func next() -> Date? {
        guard !starts.isEmpty else { return nil }
        taken += 1
        seen.append(Look(unsaved: context.hasChanges, pads: context.safeFetch(CDFetchRequest(CDDayPad.self)).count))
        if taken == savingBefore { saved = context.safeSave() }
        return starts.removeFirst()
    }
}
