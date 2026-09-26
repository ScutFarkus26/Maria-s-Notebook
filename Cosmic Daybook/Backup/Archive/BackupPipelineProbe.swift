// BackupPipelineProbe.swift
// Debug-only test seam for the backup pipeline.
//
// The export and restore paths call `BackupPipelineProbe.reach(_:)` at each
// phase ("collect", "encode <Entity>", "verify", "decode"). In a Debug build a
// test can bind a `BackupPipelineRecorder` to its task to see which thread
// each phase ran on, to act at a phase (cancel the task mid-export), or to
// hand the export fixed settings instead of the app's own. The
// recorder is a task-local, so it follows the work into `@concurrent`
// functions (same task, different executor) and concurrent tests never see
// each other's recorders. Release builds compile `reach(_:)` to nothing.

import Foundation
#if DEBUG
import Synchronization
#endif

nonisolated enum BackupPipelineProbe {
    /// Marks that the pipeline reached `phase`. A no-op unless a Debug-build
    /// test bound a recorder to the current task; the phase name is only
    /// built when one is bound.
    @inline(__always)
    static func reach(_ phase: @autoclosure () -> String) {
        #if DEBUG
        BackupPipelineRecorder.current?.record(phase())
        #endif
    }
}

#if DEBUG
/// What a test binds with `BackupPipelineRecorder.$current.withValue(recorder) { … }`.
nonisolated final class BackupPipelineRecorder: Sendable {
    @TaskLocal static var current: BackupPipelineRecorder?

    struct Step: Sendable, Equatable {
        let phase: String
        let onMainThread: Bool
    }

    private let steps = Mutex<[Step]>([])
    private let onPhase: (@Sendable (String) -> Void)?
    /// What `BackupService.buildPreferencesDTO()` returns in place of the
    /// app's settings. Those live in process-wide UserDefaults, which other
    /// suites write while a test runs, so a test that compares two reads of
    /// them (the export's, then the old collector's) binds fixed ones.
    let preferences: PreferencesDTO?

    /// `onPhase` runs synchronously on the pipeline's own thread, inside its
    /// task, each time a phase is reached.
    init(preferences: PreferencesDTO? = nil, onPhase: (@Sendable (String) -> Void)? = nil) {
        self.preferences = preferences
        self.onPhase = onPhase
    }

    fileprivate func record(_ phase: String) {
        let step = Step(phase: phase, onMainThread: Thread.isMainThread)
        steps.withLock { $0.append(step) }
        onPhase?(phase)
    }

    /// Every phase reached so far, in order.
    var reached: [Step] {
        steps.withLock { $0 }
    }
}
#endif
