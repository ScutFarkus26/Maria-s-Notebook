import Foundation
import Testing
@testable import Maria_s_Notebook

@Suite("Recall retention stats")
struct RecallRetentionStatsTests {

    static let key = "2025-2026"
    static let yearStart = Date(timeIntervalSince1970: 1_756_684_800) // ~2025-09-01
    static let spring = Date(timeIntervalSince1970: 1_741_000_000)    // ~2025-03 (before year start)
    static let fall = Date(timeIntervalSince1970: 1_757_000_000)      // ~2025-09-04 (after year start)

    func row(
        _ student: String, _ outcome: RecallOutcome, _ source: RecallSource = .observed,
        year: String? = RecallRetentionStatsTests.key,
        mastered: Date? = nil, checked: Date? = RecallRetentionStatsTests.fall
    ) -> RecallStatRow {
        RecallStatRow(studentID: student, outcome: outcome, source: source,
                      schoolYearKey: year, originalMasteredAt: mastered, checkedAt: checked)
    }

    @Test("Summary counts observed by outcome and covered separately")
    func summaryCounts() {
        let rows = [
            row("S1", .retained), row("S2", .retained),
            row("S1", .shaky), row("S2", .forgotten),
            row("S1", .retained, .covered), row("S1", .retained, .covered), row("S2", .retained, .covered)
        ]
        let s = RecallRetentionStats.summary(rows: rows, schoolYearKey: Self.key)
        #expect(s.observedCount == 4)
        #expect(s.retainedCount == 2)
        #expect(s.shakyCount == 1)
        #expect(s.forgottenCount == 1)
        #expect(s.coveredCount == 3)
        #expect(s.retentionPercent == 50)
        #expect(s.representCount == 1)
    }

    @Test("Rows from another school year are excluded")
    func otherYearExcluded() {
        let rows = [row("S1", .retained), row("S1", .forgotten, year: "2024-2025")]
        let s = RecallRetentionStats.summary(rows: rows, schoolYearKey: Self.key)
        #expect(s.observedCount == 1)
        #expect(s.retentionPercent == 100)
    }

    @Test("Retention percent is nil with no observed checks")
    func nilWhenEmpty() {
        let s = RecallRetentionStats.summary(rows: [], schoolYearKey: Self.key)
        #expect(s.retentionPercent == nil)
        #expect(!s.hasAnything)
    }

    @Test("Per-student retention groups observed checks")
    func perStudent() {
        let rows = [
            row("S1", .retained), row("S1", .shaky),
            row("S2", .retained), row("S2", .retained),
            row("S1", .retained, .covered) // covered excluded from observed math
        ]
        let perStudent = RecallRetentionStats.perStudent(rows: rows, schoolYearKey: Self.key)
        let s1 = perStudent.first { $0.id == "S1" }!
        let s2 = perStudent.first { $0.id == "S2" }!
        #expect(s1.observedCount == 2)
        #expect(s1.percent == 50)
        #expect(s2.percent == 100)
    }

    @Test("Fade-over-summer is the faded share of prior-year mastery checked this year")
    func fadeOverSummer() {
        let rows = [
            row("S1", .retained, mastered: Self.spring, checked: Self.fall),
            row("S2", .retained, mastered: Self.spring, checked: Self.fall),
            row("S1", .shaky, mastered: Self.spring, checked: Self.fall),
            row("S2", .forgotten, mastered: Self.spring, checked: Self.fall),
            // mastered this year (not summer) — excluded from the fade metric
            row("S1", .forgotten, mastered: Self.fall, checked: Self.fall)
        ]
        let pct = RecallRetentionStats.fadeOverSummerPercent(rows: rows, schoolYearKey: Self.key, yearStart: Self.yearStart)
        #expect(pct == 50) // 2 faded of 4 summer checks
    }

    @Test("Fade-over-summer is nil when nothing qualifies")
    func fadeNil() {
        let rows = [row("S1", .retained, mastered: Self.fall, checked: Self.fall)]
        let pct = RecallRetentionStats.fadeOverSummerPercent(rows: rows, schoolYearKey: Self.key, yearStart: Self.yearStart)
        #expect(pct == nil)
    }
}
