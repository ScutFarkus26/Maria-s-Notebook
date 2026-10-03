// AlbumFoldProbe.swift
// Debug-only test seam for the album search's text fold.
//
// `AlbumTextFolds.fold` calls `AlbumFoldProbe.reach(_:)` as it folds each
// album ("fold <album id>"). In a Debug build a test can bind an
// `AlbumFoldRecorder` to its task to see which albums were folded, how many
// times, and on which thread, or to hold a fold at that point. The recorder is
// a task-local, so it follows the search into the fold's task and its
// `@concurrent` work, and concurrent tests never see each other's recorders.
// Release builds compile `reach(_:)` to nothing. (The same pattern as
// `BackupPipelineProbe`.)

import Foundation
#if DEBUG
import Synchronization
#endif

nonisolated enum AlbumFoldProbe {
    /// Marks that the fold reached `step`. A no-op unless a Debug-build test
    /// bound a recorder to the current task; the step's name is only built
    /// when one is bound.
    @inline(__always)
    static func reach(_ step: @autoclosure () -> String) {
        #if DEBUG
        AlbumFoldRecorder.current?.record(step())
        #endif
    }
}

#if DEBUG
/// What a test binds with `AlbumFoldRecorder.$current.withValue(recorder) { … }`.
nonisolated final class AlbumFoldRecorder: Sendable {
    @TaskLocal static var current: AlbumFoldRecorder?

    struct Step: Sendable, Equatable {
        let name: String
        let onMainThread: Bool
    }

    private let steps = Mutex<[Step]>([])
    private let onStep: (@Sendable (String) -> Void)?

    /// `onStep` runs synchronously on the fold's own thread each time a step
    /// is reached, so a test can hold the fold there.
    init(onStep: (@Sendable (String) -> Void)? = nil) {
        self.onStep = onStep
    }

    fileprivate func record(_ step: String) {
        let reached = Step(name: step, onMainThread: Thread.isMainThread)
        steps.withLock { $0.append(reached) }
        onStep?(step)
    }

    /// Every step reached so far, in order.
    var reached: [Step] {
        steps.withLock { $0 }
    }
}
#endif
