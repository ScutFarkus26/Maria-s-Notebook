import Combine
import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// The presentation history kept live whole-table `@FetchRequest`s (every
// note, every presented assignment) only to count rows and reload when a count
// moved. A TabView keeps it alive behind other iPad tabs, so every save and
// import went through them. It now takes the same counts with `count(for:)`
// when those tables change while the screen is on screen. These pin the counts
// against change-tracking fetched-results controllers (what a `@FetchRequest`
// is) across saved rows, unsaved edits and a save merged in from another
// context, the notes the history's caches read, and the note signal that says
// when to recount. (The Group Planner, which did the same, was replaced by the
// Groups page in 2026-10.)

@Suite("Hidden-tab change counts")
@MainActor
struct HiddenTabChangeCountsTests {

    /// A fetched-results controller that tracks changes, as a `@FetchRequest`'s
    /// does (one without a delegate never moves after its first fetch).
    private final class LiveFetch: NSObject, NSFetchedResultsControllerDelegate {
        private let controller: NSFetchedResultsController<NSManagedObject>

        init(
            _ entityName: String, predicate: NSPredicate? = nil, sortKey: String,
            in context: NSManagedObjectContext
        ) throws {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.predicate = predicate
            request.sortDescriptors = [NSSortDescriptor(key: sortKey, ascending: false)]
            controller = NSFetchedResultsController(
                fetchRequest: request, managedObjectContext: context,
                sectionNameKeyPath: nil, cacheName: nil
            )
            super.init()
            controller.delegate = self
            try controller.performFetch()
        }

        var count: Int { controller.fetchedObjects?.count ?? 0 }

        nonisolated func controllerDidChangeContent(
            _ controller: NSFetchedResultsController<any NSFetchRequestResult>
        ) {}
    }

    @MainActor
    private final class Counter {
        var value = 0
    }

    /// A view context over the two real SQLite stores that merges other
    /// contexts' saves, as the app's does, and a background context beside it.
    private func sqliteContexts() throws -> (view: NSManagedObjectContext, background: NSManagedObjectContext) {
        let view = try CoreDataTestHelpers.makeSplitStoreContext()
        view.automaticallyMergesChangesFromParent = true
        let background = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        background.persistentStoreCoordinator = view.persistentStoreCoordinator
        return (view, background)
    }

    private func waitUntil(_ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    /// Runs everything already queued on the main queue (the signal delivers
    /// there), twice, so a delivery queued by a block that was queued runs too.
    private func drainMainQueue() async {
        for _ in 0..<2 {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    private func assignment(
        _ state: LessonAssignmentState, in context: NSManagedObjectContext
    ) -> CDLessonAssignment {
        let assignment = CDLessonAssignment(context: context)
        assignment.lessonID = UUID().uuidString
        assignment.studentIDs = [UUID().uuidString]
        switch state {
        case .presented: assignment.markPresented(at: Date(timeIntervalSince1970: 1_780_000_000))
        case .scheduled: assignment.schedule(onDay: Date(timeIntervalSince1970: 1_781_000_000))
        case .draft: break
        }
        return assignment
    }

    // MARK: - Presentation history

    @Test("The history's counts are what its two live fetches held: saved, unsaved, merged")
    func historyCountsMatchLiveFetches() async throws {
        let (context, background) = try sqliteContexts()
        // The history's own predicate, literal and all.
        let presented = try LiveFetch(
            "LessonAssignment", predicate: NSPredicate(format: "stateRaw == \"presented\""),
            sortKey: "presentedAt", in: context
        )
        let notes = try LiveFetch("Note", sortKey: "createdAt", in: context)
        func expectMatch(_ comment: Comment) {
            #expect(LessonAssignmentHistoryView.presentedAssignmentCount(in: context) == presented.count, comment)
            #expect(LessonAssignmentHistoryView.noteCount(in: context) == notes.count, comment)
        }
        expectMatch("empty store")

        let given = (0..<3).map { _ in assignment(.presented, in: context) }
        let scheduled = assignment(.scheduled, in: context)
        let attached = (0..<3).map { _ in CoreDataTestHelpers.seedNote(in: context) }
        attached[0].lessonAssignment = given[0]
        attached[1].lessonAssignment = given[0]
        attached[2].lessonAssignment = scheduled
        let loose = (0..<2).map { _ in CoreDataTestHelpers.seedNote(in: context) }
        #expect(CoreDataTestHelpers.save(context))
        #expect(presented.count == 3)
        #expect(notes.count == 5)
        expectMatch("saved rows")

        // Unsaved: the scheduled one given, a given one deleted, a note added
        // and a note deleted.
        scheduled.markPresented(at: Date(timeIntervalSince1970: 1_782_000_000))
        context.delete(given[2])
        CoreDataTestHelpers.seedNote(in: context).lessonAssignment = given[1]
        context.delete(loose[0])
        context.processPendingChanges()
        #expect(presented.count == 3)
        expectMatch("unsaved edits")

        #expect(CoreDataTestHelpers.save(context))
        expectMatch("after the save")

        let before = (presented: presented.count, notes: notes.count)
        await background.perform {
            let row = CDLessonAssignment(context: background)
            row.lessonID = UUID().uuidString
            row.markPresented(at: Date(timeIntervalSince1970: 1_783_000_000))
            let note = CDNote(context: background)
            note.body = "Merged"
            note.lessonAssignment = row
            try? background.save()
        }
        #expect(try await waitUntil {
            presented.count == before.presented + 1 && notes.count == before.notes + 1
        })
        expectMatch("merged save")
    }

    @Test("Reading only the notes with a presentation gives the caches the same per-presentation counts")
    func assignmentNotesKeepPerPresentationCounts() throws {
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        let given = assignment(.presented, in: context)
        let scheduled = assignment(.scheduled, in: context)
        let draft = assignment(.draft, in: context)
        let notes = (0..<6).map { CoreDataTestHelpers.seedNote(in: context, body: "Note \($0)") }
        notes[0].lessonAssignment = given
        notes[1].lessonAssignment = given
        notes[2].lessonAssignment = scheduled
        #expect(CoreDataTestHelpers.save(context))
        // Unsaved: a note moved to the draft, one attached, one detached.
        notes[1].lessonAssignment = draft
        notes[3].lessonAssignment = given
        notes[2].lessonAssignment = nil

        /// What `buildCachesAsync` builds from the notes it is given.
        func perPresentation(_ notes: [CDNote]) -> [String: Int] {
            notes.compactMap { $0.lessonAssignment?.id?.uuidString }
                .reduce(into: [:]) { counts, id in counts[id, default: 0] += 1 }
        }
        // The old notes fetch: every note, newest first.
        let every = NSFetchRequest<CDNote>(entityName: "Note")
        every.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        let expected = perPresentation(try context.fetch(every))

        #expect(perPresentation(LessonAssignmentHistoryView.assignmentNotes(in: context)) == expected)
        #expect(expected == [try #require(given.id?.uuidString): 2, try #require(draft.id?.uuidString): 1])
    }

    @Test("The note signal fires for note edits and other contexts' note saves, not other entities")
    func noteSignalScope() async throws {
        let (context, background) = try sqliteContexts()
        let received = Counter()
        let subscription = LessonAssignmentHistoryView.noteChanges(in: context).sink { _ in received.value += 1 }
        defer { subscription.cancel() }

        // An unsaved note on the view context: seen before it is saved.
        CoreDataTestHelpers.seedNote(in: context)
        context.processPendingChanges()
        await drainMainQueue()
        #expect(received.value >= 1)
        #expect(CoreDataTestHelpers.save(context))
        await drainMainQueue()

        // Another entity, edited and saved here or saved elsewhere: nothing.
        var baseline = received.value
        CoreDataTestHelpers.seedLesson(in: context)
        context.processPendingChanges()
        #expect(CoreDataTestHelpers.save(context))
        await background.perform {
            let lesson = CDLesson(context: background)
            lesson.name = "Elsewhere"
            try? background.save()
        }
        await drainMainQueue()
        #expect(received.value == baseline)

        // A note saved on another context of this coordinator: seen.
        await background.perform {
            let note = CDNote(context: background)
            note.body = "Elsewhere"
            try? background.save()
        }
        #expect(try await waitUntil { received.value > baseline })
        await drainMainQueue()

        // A note saved in another store entirely: not this screen's.
        baseline = received.value
        let other = try CoreDataTestHelpers.makeSplitStoreContext()
        CoreDataTestHelpers.seedNote(in: other)
        #expect(CoreDataTestHelpers.save(other))
        await drainMainQueue()
        #expect(received.value == baseline)
    }
}
