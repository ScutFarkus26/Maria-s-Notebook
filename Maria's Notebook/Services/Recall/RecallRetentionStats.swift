// RecallRetentionStats.swift
// Pure retention math over recall rows — the "track it" payoff. Observed checks drive the
// numbers; covered (inferred) rows are counted separately so a retention % never overstates
// what was actually observed. Reads the originalMasteredAt snapshot on each row, so no
// cross-store join to mastery is needed (recall lives in the private store, mastery in shared).

import Foundation

/// A recall row reduced to what the stats need.
struct RecallStatRow: Sendable {
    let studentID: String
    let outcome: RecallOutcome
    let source: RecallSource
    let schoolYearKey: String?
    let originalMasteredAt: Date?
    let checkedAt: Date?
}

enum RecallRetentionStats {

    struct Summary: Sendable, Equatable {
        let observedCount: Int
        let retainedCount: Int
        let shakyCount: Int
        let forgottenCount: Int
        let coveredCount: Int

        /// Share of observed checks that came back retained, rounded to a whole percent.
        /// nil when nothing has been observed yet.
        var retentionPercent: Int? {
            guard observedCount > 0 else { return nil }
            return Int((Double(retainedCount) / Double(observedCount) * 100).rounded())
        }

        /// Lessons that need a re-presentation (came back forgotten).
        var representCount: Int { forgottenCount }

        var hasAnything: Bool { observedCount > 0 || coveredCount > 0 }
    }

    /// Class-wide summary for a school year.
    static func summary(rows: [RecallStatRow], schoolYearKey: String) -> Summary {
        let thisYear = rows.filter { $0.schoolYearKey == schoolYearKey }
        let observed = thisYear.filter { $0.source == .observed }
        return Summary(
            observedCount: observed.count,
            retainedCount: observed.filter { $0.outcome == .retained }.count,
            shakyCount: observed.filter { $0.outcome == .shaky }.count,
            forgottenCount: observed.filter { $0.outcome == .forgotten }.count,
            coveredCount: thisYear.filter { $0.source == .covered }.count
        )
    }

    struct StudentRetention: Sendable, Identifiable, Equatable {
        let id: String   // studentID
        let observedCount: Int
        let retainedCount: Int

        var percent: Int? {
            guard observedCount > 0 else { return nil }
            return Int((Double(retainedCount) / Double(observedCount) * 100).rounded())
        }
    }

    /// Per-student retention (observed checks only) for a school year.
    static func perStudent(rows: [RecallStatRow], schoolYearKey: String) -> [StudentRetention] {
        let observed = rows.filter { $0.schoolYearKey == schoolYearKey && $0.source == .observed }
        return Dictionary(grouping: observed) { $0.studentID }.map { studentID, rows in
            StudentRetention(
                id: studentID,
                observedCount: rows.count,
                retainedCount: rows.filter { $0.outcome == .retained }.count
            )
        }
    }

    /// Of the observed checks on lessons mastered *before* this year and checked *during* it,
    /// the share that came back shaky/forgotten — the "fades over summer" signal. nil when no
    /// such checks exist.
    static func fadeOverSummerPercent(rows: [RecallStatRow], schoolYearKey: String, yearStart: Date) -> Int? {
        let summerChecks = rows.filter {
            $0.schoolYearKey == schoolYearKey && $0.source == .observed
                && ($0.originalMasteredAt.map { $0 < yearStart } ?? false)
                && ($0.checkedAt.map { $0 >= yearStart } ?? false)
        }
        guard !summerChecks.isEmpty else { return nil }
        let faded = summerChecks.filter { $0.outcome != .retained }.count
        return Int((Double(faded) / Double(summerChecks.count) * 100).rounded())
    }
}
