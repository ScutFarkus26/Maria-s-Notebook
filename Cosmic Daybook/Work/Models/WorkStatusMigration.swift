// WorkStatusMigration.swift
// Folds the retired completion outcome into the single work status.
//
// Before 2026-09-15 a closed work row said two things: `statusRaw == "complete"`
// and, sometimes, a `completionOutcomeRaw` naming how it went. `WorkStatus`
// now says both in one word. This is the one table that translates the old
// pair into the new raw value; the launch repair and the backup importer both
// read it, so a row restored from an old backup and a row synced from an old
// device land in the same place.

import Foundation

nonisolated enum WorkStatusMigration {

    /// The legacy pair → the merged `statusRaw`.
    ///
    /// Only a `"complete"` row with an outcome changes. Open rows keep their
    /// raw value whatever the outcome column says, a closed row with no
    /// outcome (or a retired one — `needsReview` and `notApplicable` were
    /// verdicts the merged vocabulary does not keep) stays `"complete"`
    /// (`WorkStatus.done`), and a raw value that is already one of the new
    /// closed words is left alone, which is what makes the pass idempotent.
    static func merged(statusRaw: String, outcomeRaw: String?) -> String {
        guard statusRaw == WorkStatus.done.rawValue, let outcomeRaw else { return statusRaw }
        switch CompletionOutcome(rawValue: outcomeRaw) {
        case .proficient: return WorkStatus.mastered.rawValue
        case .needsMorePractice: return WorkStatus.keepPracticing.rawValue
        case .incomplete: return WorkStatus.incomplete.rawValue
        case .needsReview, .notApplicable, .none: return statusRaw
        }
    }

    /// The merged status, tolerating a raw value no build has ever written.
    static func mergedStatus(statusRaw: String, outcomeRaw: String?) -> WorkStatus {
        WorkStatus(rawValue: merged(statusRaw: statusRaw, outcomeRaw: outcomeRaw)) ?? .active
    }
}
