// TodayViewModel+ReadyForNext.swift
// The ready queue Today shows. The rebuild itself — the change gate, the
// record read off the main thread, the numbered rebuilds — is
// `ReadyQueueLoader`, which the Groups page also owns one of; Today keeps the
// surface it always had and hands every call to its loader.

import CoreData
import Foundation

extension TodayViewModel {

    /// Everything the ready queue reads (see `ReadyQueueLoader.inputEntities`).
    nonisolated static var readyForNextInputEntities: Set<String> { ReadyQueueLoader.inputEntities }

    /// Who the record says is waiting on a next lesson — the capture-time
    /// confirmations and mastery marks, turned into the lessons they point at.
    var readyForNext: [ReadyForNextItem] { readyQueue.items }

    /// How many times the queue has been built (for tests pinning the gate).
    var readyForNextBuildCount: Int { readyQueue.buildCount }
    /// How many rebuilds have published (for tests pinning that an overtaken
    /// one never does).
    var readyForNextPublishCount: Int { readyQueue.publishCount }
    /// The rebuild whose record read is running off the main thread, if any.
    var readyForNextTask: Task<Void, Never>? { readyQueue.task }

    /// The live lesson catalog bound to `context`, when the view supplies one.
    var lessonCatalog: LessonCatalog? {
        get { readyQueue.lessonCatalog }
        set { readyQueue.lessonCatalog = newValue }
    }

    /// Marks the ready queue stale so the next `reload()` rebuilds it (on appear).
    func invalidateReadyForNext() {
        readyQueue.invalidate()
    }

    /// Rebuilds `readyForNext` only when one of its inputs changed since the
    /// last build. It reads no date, level filter or attendance, so every other
    /// reload would rebuild it to the same value.
    func refreshReadyForNextIfNeeded() {
        readyQueue.refreshIfNeeded()
    }

    /// The ready queue, built synchronously on `context` the way
    /// `students_ready` builds it (see `ReadyQueueLoader.buildItems`). Today's
    /// rebuild publishes this same queue; its tests compare against this.
    static func buildReadyForNext(lessons: [CDLesson]?, in context: NSManagedObjectContext) -> [ReadyForNextItem] {
        ReadyQueueLoader.buildItems(lessons: lessons, in: context)
    }
}
