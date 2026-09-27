// TodayViewModel+ReadyForNext.swift
// The ready queue Today shows, kept between reloads and rebuilt only when
// one of the entities it reads changes (see `ManagedObjectChangeFlag`).
//
// The rebuild's biggest part, the whole-record `PresentationRecordIndex`, is
// read and folded off the main thread (`readInBackground`) whenever the view
// context holds no unsaved edit to the rows it reads; the queue is finished
// and published on the main actor. Every rebuild takes a number, and one
// that finishes after a newer one has started is dropped, so a slow rebuild
// can never overwrite a newer queue.

import CoreData
import Foundation

extension TodayViewModel {

    /// Everything the ready queue reads: the roster, the lesson library, the
    /// three record shapes the index folds, the practice work (and its
    /// participants, which say whether it is complete), and the sub-area rules.
    nonisolated static let readyForNextInputEntities: Set<String> = [
        "Student", "Lesson", "LessonPresentation", "LessonAssignment", "YearPlanEntry",
        "WorkModel", "WorkParticipantEntity", "LessonSequenceSettings"
    ]

    /// Marks the ready queue stale so the next `reload()` rebuilds it (on appear).
    func invalidateReadyForNext() {
        readyForNextInputs.markDirty()
    }

    /// Rebuilds `readyForNext` only when one of its inputs changed since the
    /// last build. It reads no date, level filter or attendance, so every other
    /// reload would rebuild it to the same value.
    func refreshReadyForNextIfNeeded() {
        let hiddenNames = TestStudentsFilter.normalizedHiddenNames()
        let inputsMoved = readyForNextInputs.consume(pendingIn: context)
        guard inputsMoved || hiddenNames != readyForNextHiddenNames else { return }
        readyForNextHiddenNames = hiddenNames
        readyForNextBuildCount += 1
        rebuildReadyForNext()
    }

    /// Starts a rebuild under a new number, dropping any still running.
    ///
    /// The roster is read here, on the view context, as before. When the view
    /// context's own record read would be the column read (see
    /// `PresentationRecordIndex.readPath`), the index is read and folded on a
    /// background context instead, and the queue is finished when it comes
    /// back. With an unsaved record edit, which only the view context can see,
    /// or no coordinator to read from, it is all built here as it always was.
    private func rebuildReadyForNext() {
        readyForNextTask?.cancel()
        readyForNextTask = nil
        readyForNextGeneration += 1
        let generation = readyForNextGeneration

        let studentIDs = Self.readyForNextStudentIDs(in: context)
        guard !studentIDs.isEmpty else {
            publishReadyForNext([], generation: generation)
            return
        }
        guard PresentationRecordIndex.readPath(lessonIDs: nil, in: context) == .columns,
              let coordinator = context.persistentStoreCoordinator else {
            let index = PresentationRecordIndex(students: Set(studentIDs), in: context)
            finishReadyForNext(index: index, studentIDs: studentIDs, generation: generation)
            return
        }
        let students = Set(studentIDs)
        // `.userInitiated`: the queue is on the screen the guide is looking at,
        // and its first build is what Today's first appearance waits on.
        readyForNextTask = Task(priority: .userInitiated) { [weak self] in
            let index = await PresentationRecordIndex.readInBackground(students: students, from: coordinator)
            guard let self, !Task.isCancelled else { return }
            finishReadyForNext(index: index, studentIDs: studentIDs, generation: generation)
        }
    }

    /// Builds the queue from a record index and publishes it, unless a newer
    /// rebuild has started since this one did.
    func finishReadyForNext(index: PresentationRecordIndex, studentIDs: [String], generation: Int) {
        guard generation == readyForNextGeneration else { return }
        let lessons = readyForNextLessons() ?? context.safeFetch(CDFetchRequest(CDLesson.self))
        let items = ReadyForNextEngine.items(studentIDs: studentIDs, lessons: lessons, index: index, in: context)
        publishReadyForNext(items, generation: generation)
    }

    private func publishReadyForNext(_ items: [ReadyForNextItem], generation: Int) {
        guard generation == readyForNextGeneration else { return }
        readyForNextTask = nil
        readyForNextPublishCount += 1
        readyForNext = items
    }

    /// The live catalog when it is bound to this context and has no
    /// unannounced lesson edit to catch up on; a fetch otherwise.
    private func readyForNextLessons() -> [CDLesson]? {
        if let catalog = lessonCatalog, catalog.context === context,
           !ManagedObjectChangeFlag.hasPendingChanges(to: ["Lesson"], in: context) {
            return catalog.all
        }
        return nil
    }

    /// The ready queue, built the way `students_ready` builds it: the enrolled
    /// roster, the whole lesson library, and one record index over all three
    /// record shapes. Three fetches and dictionary lookups from there — no
    /// per-child or per-row work, so it costs the same whatever Today holds.
    /// `lessons` nil fetches the library.
    ///
    /// All on the calling context, synchronously. Today's rebuild publishes
    /// this same queue with the index read off the main thread; its tests
    /// compare against this.
    static func buildReadyForNext(lessons: [CDLesson]?, in context: NSManagedObjectContext) -> [ReadyForNextItem] {
        let studentIDs = readyForNextStudentIDs(in: context)
        guard !studentIDs.isEmpty else { return [] }

        let lessons = lessons ?? context.safeFetch(CDFetchRequest(CDLesson.self))
        guard !lessons.isEmpty else { return [] }

        let index = PresentationRecordIndex(students: Set(studentIDs), in: context)
        return ReadyForNextEngine.items(
            studentIDs: studentIDs, lessons: lessons, index: index, in: context
        )
    }

    /// The children the queue considers: enrolled and not hidden test
    /// students, as id strings.
    static func readyForNextStudentIDs(in context: NSManagedObjectContext) -> [String] {
        DataQueryService(context: context)
            .fetchAllStudents(excludeTest: true, excludeWithdrawn: true)
            .compactMap { $0.id?.uuidString }
    }
}
