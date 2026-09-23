// TodayViewModel+ReadyForNext.swift
// The ready queue Today shows, kept between reloads and rebuilt only when
// one of the entities it reads changes (see `ManagedObjectChangeFlag`).

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
        readyForNext = Self.buildReadyForNext(lessons: readyForNextLessons(), in: context)
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
    static func buildReadyForNext(lessons: [CDLesson]?, in context: NSManagedObjectContext) -> [ReadyForNextItem] {
        let students = DataQueryService(context: context)
            .fetchAllStudents(excludeTest: true, excludeWithdrawn: true)
        let studentIDs = students.compactMap { $0.id?.uuidString }
        guard !studentIDs.isEmpty else { return [] }

        let lessons = lessons ?? context.safeFetch(CDFetchRequest(CDLesson.self))
        guard !lessons.isEmpty else { return [] }

        let index = PresentationRecordIndex(students: Set(studentIDs), in: context)
        return ReadyForNextEngine.items(
            studentIDs: studentIDs, lessons: lessons, index: index, in: context
        )
    }
}
