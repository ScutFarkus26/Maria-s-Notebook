// RecallFrontierEngine.swift
// Pure, Core-Data-free core of the Lesson Recall feature. Given a student's mastered lessons,
// the curriculum, and existing recall rows, it computes the recall queue collapsed to each
// strand's "frontier" (the most advanced mastered lesson), the lessons that frontier "covers",
// the covered-stamp intents to persist when a frontier is confirmed retained, and the
// drill-down lesson to surface when a frontier comes back shaky/forgotten.
//
// Kept pure (value types in, value types out, no fetches/writes) so it is exhaustively unit
// testable — mirroring the purity of BlockingAlgorithmEngine and the SchoolYear math.

import Foundation

// MARK: - Inputs

/// A curriculum lesson, reduced to what the frontier math needs. `area`/`sequence` are expected
/// pre-trimmed (display casing) by the caller, matching ProgressDashboardViewModel's grouping.
struct RecallLesson: Sendable, Hashable {
    let id: UUID
    let name: String
    let area: String
    let sequence: String
    let orderInSequence: Int
}

/// A lesson a student has mastered (a `CDLessonPresentation` with `state == .proficient`).
/// `lessonID` is a normalized uuidString. `masteredAt` may be nil (fail-open).
struct RecallMastery: Sendable {
    let studentID: String
    let lessonID: String
    let masteredAt: Date?
}

/// An existing `CDLessonRecallCheck` row, reduced for eligibility/idempotency decisions.
struct RecallExisting: Sendable {
    let studentID: String
    let lessonID: String
    let schoolYearKey: String?
    let source: RecallSource
    let checkedAt: Date?
}

/// Parameters that scope a queue computation to "now" and the active lens.
struct RecallConfig: Sendable {
    let schoolYearStart: Date
    let schoolYearKey: String
    /// How long after the last check (or mastery) a frontier becomes due again, in seconds.
    let spacedInterval: TimeInterval
    let now: Date
}

// MARK: - Outputs

enum RecallDueReason: String, Sendable {
    case startOfYearSweep
    case spacedDue
}

/// A lower lesson in a strand that a retained frontier implies coverage of.
struct RecallCoveredRef: Sendable, Hashable {
    let lessonID: UUID
    let name: String
    let originalMasteredAt: Date?
}

/// One row in the recall queue: a strand collapsed to its frontier lesson.
struct RecallQueueEntry: Identifiable, Sendable {
    let id: String
    let studentID: String
    let area: String
    let sequence: String
    let frontierLessonID: UUID
    let frontierLessonName: String
    let frontierOrderInSequence: Int
    let frontierMasteredAt: Date?
    let coveredLessons: [RecallCoveredRef]
    let lastCheckedAt: Date?
    let dueReason: RecallDueReason

    var coversCount: Int { coveredLessons.count }
}

/// A covered-stamp to persist (`source == .covered`, presumed retained) when a frontier is
/// confirmed retained. The engine only emits intents that don't already exist (idempotent).
struct RecallCoveredIntent: Sendable, Equatable {
    let studentID: String
    let lessonID: String
    let coveredByLessonID: String
    let originalMasteredAt: Date?
}

// MARK: - Engine

enum RecallFrontierEngine {

    /// Normalize an id string to canonical uuidString form so joins line up regardless of
    /// stored casing (matches BlockingAlgorithmEngine's normalization).
    static func normalize(_ id: String) -> String {
        UUID(uuidString: id)?.uuidString ?? id
    }

    private static func key(_ studentID: String, _ lessonID: String) -> String {
        normalize(studentID) + "|" + normalize(lessonID)
    }

    /// Build the recall queue. Returns one entry per frontier (co-frontiers at the same
    /// `orderInSequence` each produce an entry). An entry is included if it is due via the
    /// start-of-year sweep OR the spaced-recheck rule.
    static func buildQueue(
        lessons: [RecallLesson],
        mastered: [RecallMastery],
        existing: [RecallExisting],
        config: RecallConfig
    ) -> [RecallQueueEntry] {
        let lessonsByID: [String: RecallLesson] = Dictionary(
            lessons.map { (normalize($0.id.uuidString), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Existing-recall lookups.
        var observedThisYear = Set<String>()
        var coveredThisYear = Set<String>()
        var lastObserved: [String: Date] = [:]
        for row in existing {
            let k = key(row.studentID, row.lessonID)
            if row.source == .observed {
                if row.schoolYearKey == config.schoolYearKey { observedThisYear.insert(k) }
                if let checkedAt = row.checkedAt {
                    if let prev = lastObserved[k] { lastObserved[k] = max(prev, checkedAt) }
                    else { lastObserved[k] = checkedAt }
                }
            } else {
                if row.schoolYearKey == config.schoolYearKey { coveredThisYear.insert(k) }
            }
        }
        _ = coveredThisYear // reserved for future use (dashboard reads it; queue doesn't gate on it)

        // Group a student's mastered lessons into strands keyed by (student, area, sequence).
        struct StrandKey: Hashable { let studentID: String; let area: String; let sequence: String }
        struct MasteredInStrand { let lesson: RecallLesson; let masteredAt: Date? }
        var strands: [StrandKey: [MasteredInStrand]] = [:]
        for m in mastered {
            guard let lesson = lessonsByID[normalize(m.lessonID)] else { continue }
            guard !lesson.area.isEmpty, !lesson.sequence.isEmpty else { continue }
            let sk = StrandKey(studentID: normalize(m.studentID), area: lesson.area, sequence: lesson.sequence)
            strands[sk, default: []].append(MasteredInStrand(lesson: lesson, masteredAt: m.masteredAt))
        }

        var entries: [RecallQueueEntry] = []
        for (sk, items) in strands {
            let maxOrder = items.map { $0.lesson.orderInSequence }.max() ?? 0
            let frontiers = items.filter { $0.lesson.orderInSequence == maxOrder }
            let covered = items
                .filter { $0.lesson.orderInSequence < maxOrder }
                .sorted { $0.lesson.orderInSequence < $1.lesson.orderInSequence }
                .map { RecallCoveredRef(lessonID: $0.lesson.id, name: $0.lesson.name, originalMasteredAt: $0.masteredAt) }

            for frontier in frontiers {
                let frontierIDStr = normalize(frontier.lesson.id.uuidString)
                let k = key(sk.studentID, frontierIDStr)

                let masteredBeforeYear = frontier.masteredAt.map { $0 < config.schoolYearStart } ?? true
                let checkedThisYear = observedThisYear.contains(k)
                let sweepEligible = masteredBeforeYear && !checkedThisYear

                let referenceDate = lastObserved[k] ?? frontier.masteredAt
                let spacedEligible: Bool
                if let referenceDate {
                    spacedEligible = config.now.timeIntervalSince(referenceDate) >= config.spacedInterval
                } else {
                    spacedEligible = !checkedThisYear
                }

                guard sweepEligible || spacedEligible else { continue }

                entries.append(RecallQueueEntry(
                    id: "\(sk.studentID)|\(frontierIDStr)",
                    studentID: sk.studentID,
                    area: sk.area,
                    sequence: sk.sequence,
                    frontierLessonID: frontier.lesson.id,
                    frontierLessonName: frontier.lesson.name,
                    frontierOrderInSequence: frontier.lesson.orderInSequence,
                    frontierMasteredAt: frontier.masteredAt,
                    coveredLessons: covered,
                    lastCheckedAt: lastObserved[k],
                    dueReason: sweepEligible ? .startOfYearSweep : .spacedDue
                ))
            }
        }

        return entries.sorted {
            if $0.studentID != $1.studentID { return $0.studentID < $1.studentID }
            if $0.area != $1.area { return $0.area.localizedCaseInsensitiveCompare($1.area) == .orderedAscending }
            return $0.sequence.localizedCaseInsensitiveCompare($1.sequence) == .orderedAscending
        }
    }

    /// The covered-stamp intents to persist when `entry`'s frontier is confirmed retained.
    /// Skips any lower lesson that already has a recall row this school year (idempotent), so
    /// re-running a sweep or re-confirming a frontier never duplicates covered records.
    static func coveredIntents(
        forRetained entry: RecallQueueEntry,
        existing: [RecallExisting],
        schoolYearKey: String
    ) -> [RecallCoveredIntent] {
        var seenThisYear = Set<String>()
        for row in existing where row.schoolYearKey == schoolYearKey {
            seenThisYear.insert(key(row.studentID, row.lessonID))
        }
        let frontierIDStr = normalize(entry.frontierLessonID.uuidString)
        return entry.coveredLessons.compactMap { ref in
            let lessonIDStr = normalize(ref.lessonID.uuidString)
            guard !seenThisYear.contains(key(entry.studentID, lessonIDStr)) else { return nil }
            return RecallCoveredIntent(
                studentID: entry.studentID,
                lessonID: lessonIDStr,
                coveredByLessonID: frontierIDStr,
                originalMasteredAt: ref.originalMasteredAt
            )
        }
    }

    /// The next lesson *below* `lessonID` within its strand — surfaced for the drill-down when a
    /// frontier comes back shaky/forgotten. Returns nil if `lessonID` is the lowest rung.
    static func precedingLesson(
        below lessonID: UUID,
        area: String,
        sequence: String,
        lessons: [RecallLesson]
    ) -> RecallLesson? {
        let strand = lessons
            .filter { $0.area == area && $0.sequence == sequence }
            .sorted { $0.orderInSequence < $1.orderInSequence }
        guard let idx = strand.firstIndex(where: { $0.id == lessonID }), idx > 0 else { return nil }
        return strand[idx - 1]
    }
}
