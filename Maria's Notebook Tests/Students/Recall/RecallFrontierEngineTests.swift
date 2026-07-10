import Foundation
import Testing
@testable import Maria_s_Notebook

// MARK: - RecallFrontierEngine (pure core)
//
// Exhaustive tests for the recall queue math: frontier selection, co-frontier ties, covers-N,
// covered-stamp idempotency, drill-down, and the two eligibility triggers (start-of-year sweep
// and spaced re-check). No Core Data — pure value types in, value types out.

@Suite("Recall frontier engine")
struct RecallFrontierEngineTests {

    // Fixed dates so tests are deterministic.
    static let yearStart = Date(timeIntervalSince1970: 1_756_684_800) // ~2025-09-01
    static let springMastery = Date(timeIntervalSince1970: 1_741_000_000) // ~2025-03
    static let now = Date(timeIntervalSince1970: 1_757_000_000) // ~2025-09-04
    static let key = "2025-2026"
    static let interval: TimeInterval = 90 * 86_400

    // Stable lesson IDs for a Math | Division strand (concrete -> abstract).
    static let board = UUID()
    static let stamp = UUID()
    static let racks = UUID()
    static let longDiv = UUID()

    static let divisionLessons: [RecallLesson] = [
        RecallLesson(id: board, name: "Unit division board", area: "Math", sequence: "Division", orderInSequence: 1),
        RecallLesson(id: stamp, name: "Division stamp game", area: "Math", sequence: "Division", orderInSequence: 2),
        RecallLesson(id: racks, name: "Racks & tubes", area: "Math", sequence: "Division", orderInSequence: 3),
        RecallLesson(id: longDiv, name: "Long division", area: "Math", sequence: "Division", orderInSequence: 4)
    ]

    static func config(now: Date = RecallFrontierEngineTests.now) -> RecallConfig {
        RecallConfig(schoolYearStart: yearStart, schoolYearKey: key, spacedInterval: interval, now: now)
    }

    static func masteredAll(_ student: String, at date: Date? = RecallFrontierEngineTests.springMastery) -> [RecallMastery] {
        [board, stamp, racks, longDiv].map {
            RecallMastery(studentID: student, lessonID: $0.uuidString, masteredAt: date)
        }
    }

    // MARK: - Frontier + covers

    @Test("Frontier is the highest mastered lesson; it covers the lower three")
    func frontierAndCovers() {
        let entries = RecallFrontierEngine.buildQueue(
            lessons: Self.divisionLessons,
            mastered: Self.masteredAll("S1"),
            existing: [],
            config: Self.config()
        )
        #expect(entries.count == 1)
        let entry = try! #require(entries.first)
        #expect(entry.frontierLessonID == Self.longDiv)
        #expect(entry.frontierOrderInSequence == 4)
        #expect(entry.coversCount == 3)
        #expect(Set(entry.coveredLessons.map(\.lessonID)) == [Self.board, Self.stamp, Self.racks])
        #expect(entry.dueReason == .startOfYearSweep)
    }

    @Test("A strand with only one mastered lesson covers nothing")
    func standsAlone() {
        let mastered = [RecallMastery(studentID: "S1", lessonID: Self.longDiv.uuidString, masteredAt: Self.springMastery)]
        let entries = RecallFrontierEngine.buildQueue(
            lessons: Self.divisionLessons, mastered: mastered, existing: [], config: Self.config()
        )
        #expect(entries.count == 1)
        #expect(entries.first?.coversCount == 0)
    }

    @Test("Co-frontier ties at the same orderInSequence each produce an entry")
    func coFrontierTies() {
        let tieA = UUID(), tieB = UUID()
        let lessons = [
            RecallLesson(id: Self.board, name: "Board", area: "Math", sequence: "Division", orderInSequence: 1),
            RecallLesson(id: tieA, name: "Tie A", area: "Math", sequence: "Division", orderInSequence: 2),
            RecallLesson(id: tieB, name: "Tie B", area: "Math", sequence: "Division", orderInSequence: 2)
        ]
        let mastered = [Self.board, tieA, tieB].map {
            RecallMastery(studentID: "S1", lessonID: $0.uuidString, masteredAt: Self.springMastery)
        }
        let entries = RecallFrontierEngine.buildQueue(lessons: lessons, mastered: mastered, existing: [], config: Self.config())
        #expect(entries.count == 2)
        #expect(Set(entries.map(\.frontierLessonID)) == [tieA, tieB])
        // Both tied frontiers cover only the strictly-lower board.
        #expect(entries.allSatisfy { $0.coversCount == 1 })
    }

    // MARK: - Eligibility (both triggers)

    @Test("Start-of-year sweep: mastered before year start and not checked this year")
    func sweepEligible() {
        let entries = RecallFrontierEngine.buildQueue(
            lessons: Self.divisionLessons, mastered: Self.masteredAll("S1"), existing: [], config: Self.config()
        )
        #expect(entries.first?.dueReason == .startOfYearSweep)
    }

    @Test("Frontier already checked this year drops out of the queue")
    func checkedThisYearExcluded() {
        let existing = [RecallExisting(
            studentID: "S1", lessonID: Self.longDiv.uuidString, schoolYearKey: Self.key,
            source: .observed, checkedAt: Self.now
        )]
        let entries = RecallFrontierEngine.buildQueue(
            lessons: Self.divisionLessons, mastered: Self.masteredAll("S1"), existing: existing, config: Self.config()
        )
        #expect(entries.isEmpty)
    }

    @Test("Spaced re-check: mastered this year but last seen beyond the interval")
    func spacedDue() {
        // Mastered after year start, last checked 120 days ago — not a sweep, but spaced-due.
        let masteredRecent = Self.now.addingTimeInterval(-200 * 86_400) // after yearStart, > interval ago
        let lastCheck = Self.now.addingTimeInterval(-120 * 86_400)
        let mastered = [RecallMastery(studentID: "S1", lessonID: Self.longDiv.uuidString, masteredAt: masteredRecent)]
        let existing = [RecallExisting(
            studentID: "S1", lessonID: Self.longDiv.uuidString, schoolYearKey: Self.key,
            source: .observed, checkedAt: lastCheck
        )]
        let entries = RecallFrontierEngine.buildQueue(
            lessons: Self.divisionLessons, mastered: mastered, existing: existing, config: Self.config()
        )
        // Checked this year, so not a sweep; but 120d > 90d interval, so spaced-due.
        #expect(entries.count == 1)
        #expect(entries.first?.dueReason == .spacedDue)
    }

    @Test("Recently checked frontier is not due")
    func recentlyCheckedNotDue() {
        let masteredRecent = Self.now.addingTimeInterval(-100 * 86_400)
        let lastCheck = Self.now.addingTimeInterval(-10 * 86_400) // within interval
        let mastered = [RecallMastery(studentID: "S1", lessonID: Self.longDiv.uuidString, masteredAt: masteredRecent)]
        let existing = [RecallExisting(
            studentID: "S1", lessonID: Self.longDiv.uuidString, schoolYearKey: Self.key,
            source: .observed, checkedAt: lastCheck
        )]
        let entries = RecallFrontierEngine.buildQueue(
            lessons: Self.divisionLessons, mastered: mastered, existing: existing, config: Self.config()
        )
        #expect(entries.isEmpty)
    }

    @Test("Proficient with nil masteredAt fails open into the sweep")
    func nilMasteredFailOpen() {
        let mastered = [RecallMastery(studentID: "S1", lessonID: Self.longDiv.uuidString, masteredAt: nil)]
        let entries = RecallFrontierEngine.buildQueue(
            lessons: Self.divisionLessons, mastered: mastered, existing: [], config: Self.config()
        )
        #expect(entries.count == 1)
        #expect(entries.first?.dueReason == .startOfYearSweep)
    }

    @Test("Students are grouped independently")
    func perStudent() {
        let mastered = Self.masteredAll("S1") + Self.masteredAll("S2")
        let entries = RecallFrontierEngine.buildQueue(
            lessons: Self.divisionLessons, mastered: mastered, existing: [], config: Self.config()
        )
        #expect(entries.count == 2)
        #expect(Set(entries.map(\.studentID)) == ["S1", "S2"])
    }

    // MARK: - Covered intents (idempotency)

    @Test("Covered intents are produced for all lowers when none exist yet")
    func coveredIntentsFresh() {
        let entry = RecallFrontierEngine.buildQueue(
            lessons: Self.divisionLessons, mastered: Self.masteredAll("S1"), existing: [], config: Self.config()
        ).first!
        let intents = RecallFrontierEngine.coveredIntents(forRetained: entry, existing: [], schoolYearKey: Self.key)
        #expect(intents.count == 3)
        #expect(intents.allSatisfy { $0.coveredByLessonID == Self.longDiv.uuidString })
    }

    @Test("Covered intents skip lowers already recorded this year (idempotent)")
    func coveredIntentsIdempotent() {
        let entry = RecallFrontierEngine.buildQueue(
            lessons: Self.divisionLessons, mastered: Self.masteredAll("S1"), existing: [], config: Self.config()
        ).first!
        let existing = [RecallExisting(
            studentID: "S1", lessonID: Self.stamp.uuidString, schoolYearKey: Self.key,
            source: .covered, checkedAt: Self.now
        )]
        let intents = RecallFrontierEngine.coveredIntents(forRetained: entry, existing: existing, schoolYearKey: Self.key)
        #expect(intents.count == 2)
        #expect(!intents.contains { $0.lessonID == Self.stamp.uuidString })
    }

    // MARK: - Drill-down

    @Test("Drill-down returns the next lesson below the frontier")
    func drillDown() {
        let below = RecallFrontierEngine.precedingLesson(
            below: Self.longDiv, area: "Math", sequence: "Division", lessons: Self.divisionLessons
        )
        #expect(below?.id == Self.racks)
    }

    @Test("Drill-down at the lowest rung returns nil")
    func drillDownFloor() {
        let below = RecallFrontierEngine.precedingLesson(
            below: Self.board, area: "Math", sequence: "Division", lessons: Self.divisionLessons
        )
        #expect(below == nil)
    }
}
