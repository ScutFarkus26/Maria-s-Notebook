// BackupPipelineProbe.swift
// Debug-only test seam for the backup pipeline.
//
// The export and restore paths call `BackupPipelineProbe.reach(_:)` at each
// phase ("collect", "encode <Entity>", "verify", "decode",
// "import <Entity>"). In a Debug build a test can bind a
// `BackupPipelineRecorder` to its task to see which thread each phase ran on,
// to act at a phase (cancel the task mid-export), to make a restore fail at
// one (`reachOrFail`), or to hand the export fixed settings instead of the
// app's own. The recorder is a task-local, so it follows the work into
// `@concurrent` functions (same task, different executor) and concurrent tests
// never see each other's recorders. Release builds compile both to nothing.

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

    /// `reach(_:)`, then the error a Debug-build test's recorder names for
    /// `phase`, if any: how the restore tests fail one entity type part-way
    /// through a restore. Never throws in a Release build.
    @inline(__always)
    static func reachOrFail(_ phase: @autoclosure () -> String) throws {
        #if DEBUG
        guard let recorder = BackupPipelineRecorder.current else { return }
        let name = phase()
        recorder.record(name)
        if let error = recorder.failure?(name) { throw error }
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
    /// The error `BackupPipelineProbe.reachOrFail` throws at a phase, or nil
    /// to carry on.
    let failure: (@Sendable (String) -> (any Error)?)?

    /// `onPhase` runs synchronously on the pipeline's own thread, inside its
    /// task, each time a phase is reached; `failure` too, at the phases that
    /// can fail.
    init(
        preferences: PreferencesDTO? = nil,
        onPhase: (@Sendable (String) -> Void)? = nil,
        failure: (@Sendable (String) -> (any Error)?)? = nil
    ) {
        self.preferences = preferences
        self.onPhase = onPhase
        self.failure = failure
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
