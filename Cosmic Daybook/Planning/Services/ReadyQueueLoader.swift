//
//  ReadyQueueLoader.swift
//  Cosmic Daybook
//
//  The ready queue, kept between reloads and rebuilt only when one of the
//  entities it reads changes (see `ManagedObjectChangeFlag`). Today and the
//  Groups page each own one.
//
//  The rebuild's biggest part, the whole-record `PresentationRecordIndex`, is
//  read and folded off the main thread (`readInBackground`) whenever the view
//  context holds no unsaved edit to the rows it reads; the queue is finished
//  and published on the main actor. Every rebuild takes a number, and one
//  that finishes after a newer one has started is dropped, so a slow rebuild
//  can never overwrite a newer queue.
//
//  It publishes the queue itself (`items`, what Today and `students_ready`
//  have always shown) and the snapshot `ReadyGroups` and `SequenceLadder`
//  build from: the same queue with the record, lesson order and roster it
//  came from.
//

import CoreData
import Foundation

@Observable
@MainActor
final class ReadyQueueLoader {

    /// Everything the ready queue reads: the roster, the lesson library, the
    /// three record shapes the index folds, the practice work (and its
    /// participants, which say whether it is complete), and the sub-area rules.
    nonisolated static let inputEntities: Set<String> = [
        "Student", "Lesson", "LessonPresentation", "LessonAssignment", "YearPlanEntry",
        "WorkModel", "WorkParticipantEntity", "LessonSequenceSettings"
    ]

    let context: NSManagedObjectContext

    /// The queue, as `ReadyForNextEngine.items` returned it.
    private(set) var items: [ReadyForNextItem] = []
    /// The queue with what it was built from; nil until the first build publishes.
    private(set) var snapshot: ReadyQueueSnapshot?
    /// How many rebuilds have published. Moves exactly when `items` and
    /// `snapshot` are replaced, so a view can key derived work on it.
    private(set) var publishCount = 0

    /// Flips when one of `inputEntities` changes, so a refresh rebuilds only then.
    @ObservationIgnored private let inputs: ManagedObjectChangeFlag
    /// The test-student preference the queue was last built under; it filters
    /// the roster without touching the store.
    @ObservationIgnored private var hiddenNames: Set<String>?
    /// How many times the queue has been built (for tests pinning the gate).
    @ObservationIgnored private(set) var buildCount = 0
    /// Numbers the rebuilds: one publishes only while its number is still the
    /// latest, so an overtaken rebuild never replaces a newer queue.
    @ObservationIgnored private(set) var generation = 0
    /// The rebuild whose record read is running off the main thread, if any.
    @ObservationIgnored private(set) var task: Task<Void, Never>?
    /// The live lesson catalog bound to `context`, when the view supplies one.
    @ObservationIgnored weak var lessonCatalog: LessonCatalog?

    init(context: NSManagedObjectContext) {
        self.context = context
        inputs = ManagedObjectChangeFlag(entityNames: Self.inputEntities, context: context)
    }

    // MARK: - Refreshing

    /// Marks the queue stale so the next `refreshIfNeeded()` rebuilds it.
    func invalidate() {
        inputs.markDirty()
    }

    /// Rebuilds only when one of the inputs changed since the last build, or
    /// the test-student preference did. It reads no date, level filter or
    /// attendance, so any other refresh would rebuild it to the same value.
    func refreshIfNeeded() {
        let hiddenNames = TestStudentsFilter.normalizedHiddenNames()
        let inputsMoved = inputs.consume(pendingIn: context)
        guard inputsMoved || hiddenNames != self.hiddenNames else { return }
        self.hiddenNames = hiddenNames
        buildCount += 1
        rebuild()
    }

    /// Waits for a rebuild running off the main thread, and any rebuild that
    /// overtook it, to publish or be dropped.
    func settled() async {
        while let running = task {
            await running.value
            // A dropped rebuild leaves the newer one in its place; one that
            // published has cleared it. Anything else would never change.
            guard task != running else { return }
        }
    }

    /// Starts a rebuild under a new number, dropping any still running.
    ///
    /// The roster is read here, on the view context. When the view context's
    /// own record read would be the column read (see
    /// `PresentationRecordIndex.readPath`), the index is read and folded on a
    /// background context instead, and the queue is finished when it comes
    /// back. With an unsaved record edit, which only the view context can see,
    /// or no coordinator to read from, it is all built here.
    private func rebuild() {
        task?.cancel()
        task = nil
        generation += 1
        let generation = generation

        let students = Self.students(in: context)
        let roster = ReadyRoster(students: students)
        let studentIDs = students.compactMap { $0.id?.uuidString }
        guard !studentIDs.isEmpty else {
            publish(Self.emptySnapshot(roster: roster), generation: generation)
            return
        }
        guard PresentationRecordIndex.readPath(lessonIDs: nil, in: context) == .columns,
              let coordinator = context.persistentStoreCoordinator else {
            let index = PresentationRecordIndex(students: Set(studentIDs), in: context)
            finish(index: index, roster: roster, studentIDs: studentIDs, generation: generation)
            return
        }
        let scope = Set(studentIDs)
        // `.userInitiated`: the queue is on the screen the guide is looking at,
        // and its first build is what that screen's first appearance waits on.
        task = Task(priority: .userInitiated) { [weak self] in
            let index = await PresentationRecordIndex.readInBackground(students: scope, from: coordinator)
            guard let self, !Task.isCancelled else { return }
            finish(index: index, roster: roster, studentIDs: studentIDs, generation: generation)
        }
    }

    /// Builds the queue from a record index and publishes it, unless a newer
    /// rebuild has started since this one did.
    private func finish(
        index: PresentationRecordIndex, roster: ReadyRoster, studentIDs: [String], generation: Int
    ) {
        guard generation == self.generation else { return }
        let lessons = catalogLessons() ?? context.safeFetch(CDFetchRequest(CDLesson.self))
        let items = ReadyForNextEngine.items(studentIDs: studentIDs, lessons: lessons, index: index, in: context)
        publish(
            ReadyQueueSnapshot(
                items: items, index: index, order: LessonSequenceOrder(lessons: lessons), roster: roster
            ),
            generation: generation
        )
    }

    private func publish(_ snapshot: ReadyQueueSnapshot, generation: Int) {
        guard generation == self.generation else { return }
        task = nil
        publishCount += 1
        items = snapshot.items
        self.snapshot = snapshot
    }

    /// The live catalog when it is bound to this context and has no
    /// unannounced lesson edit to catch up on; nil means fetch.
    private func catalogLessons() -> [CDLesson]? {
        if let catalog = lessonCatalog, catalog.context === context,
           !ManagedObjectChangeFlag.hasPendingChanges(to: ["Lesson"], in: context) {
            return catalog.all
        }
        return nil
    }

    private static func emptySnapshot(roster: ReadyRoster) -> ReadyQueueSnapshot {
        ReadyQueueSnapshot(
            items: [],
            index: PresentationRecordIndex(rows: PresentationRecordIndex.RecordRows(), students: []),
            order: LessonSequenceOrder(lessons: []),
            roster: roster
        )
    }

    // MARK: - The Synchronous Build

    /// The ready queue, built the way `students_ready` builds it: the enrolled
    /// roster, the whole lesson library, and one record index over all three
    /// record shapes. Three fetches and dictionary lookups from there — no
    /// per-child or per-row work. `lessons` nil fetches the library.
    ///
    /// All on the calling context, synchronously. The loader publishes this
    /// same queue with the index read off the main thread; tests compare
    /// against this.
    static func buildItems(lessons: [CDLesson]?, in context: NSManagedObjectContext) -> [ReadyForNextItem] {
        let studentIDs = studentIDs(in: context)
        guard !studentIDs.isEmpty else { return [] }

        let lessons = lessons ?? context.safeFetch(CDFetchRequest(CDLesson.self))
        guard !lessons.isEmpty else { return [] }

        let index = PresentationRecordIndex(students: Set(studentIDs), in: context)
        return ReadyForNextEngine.items(studentIDs: studentIDs, lessons: lessons, index: index, in: context)
    }

    /// The children the queue considers: enrolled and not hidden test students.
    static func students(in context: NSManagedObjectContext) -> [CDStudent] {
        DataQueryService(context: context).fetchAllStudents(excludeTest: true, excludeWithdrawn: true)
    }

    /// `students(in:)` as id strings.
    static func studentIDs(in context: NSManagedObjectContext) -> [String] {
        students(in: context).compactMap { $0.id?.uuidString }
    }
}
