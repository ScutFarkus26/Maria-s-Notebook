import Foundation
import Testing
@testable import Maria_s_Notebook

// The Three-Year View's rules, pinned on value types. Every glyph the two
// screens and the two MCP tools draw comes from these decisions.

@Suite("Curriculum map engine")
struct CurriculumMapEngineTests {

    // MARK: - Fixtures

    private let student = UUID()
    private let peer = UUID()

    private func lesson(
        _ name: String, area: String = "Math", sequence: String = "Laws", order: Int,
        key: Bool = false, great: String? = nil, story: Bool = false
    ) -> CurriculumLessonRef {
        CurriculumLessonRef(
            id: UUID(), name: name, area: area, sequence: sequence, section: "", orderInSequence: order,
            sortIndex: order, greatLessonRaw: great, isStory: story, isKeyLesson: key
        )
    }

    private func day(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: iso)!
    }

    private func presentation(
        _ lesson: CurriculumLessonRef, on date: String?, students: [UUID]? = nil, confirmed: [UUID] = []
    ) -> CurriculumPresentationRef {
        CurriculumPresentationRef(
            id: UUID(), lessonID: lesson.id, studentIDs: students ?? [student],
            presentedAt: date.map(day), confirmedStudentIDs: confirmed
        )
    }

    private func work(
        _ lesson: CurriculumLessonRef, status: WorkStatus = .active, assigned: String, students: [UUID]? = nil
    ) -> CurriculumWorkRef {
        CurriculumWorkRef(
            id: UUID(), lessonID: lesson.id, studentIDs: students ?? [student], statusRaw: status.rawValue,
            assignedAt: day(assigned), completedAt: status.isClosed ? day(assigned) : nil, lastTouchedAt: nil
        )
    }

    private func practice(_ work: CurriculumWorkRef, on date: String, students: [UUID]? = nil) -> CurriculumPracticeRef {
        CurriculumPracticeRef(id: UUID(), date: day(date), studentIDs: students ?? [student], workIDs: [work.id])
    }

    private func cell(_ input: CurriculumMapInput, _ lesson: CurriculumLessonRef) -> CurriculumCell? {
        CurriculumMapEngine.cells(for: student, input: input)[lesson.id]
    }

    // MARK: - The Ladder

    @Test("A presentation alone is presented, with its date")
    func presentedOnly() throws {
        let laws = lesson("Commutative Law", order: 0)
        var input = CurriculumMapInput(lessons: [laws])
        input.presentations = [presentation(laws, on: "2026-02-12")]

        let cell = try #require(cell(input, laws))
        #expect(cell.state == .presented)
        #expect(cell.isPresentedNeverChosen)
        #expect(cell.firstPresented == day("2026-02-12"))
        #expect(cell.lastActivity == day("2026-02-12"))
        #expect(cell.evidence.presentationIDs.count == 1)
    }

    @Test("A bulk 'previously presented' mark with no date still counts as presented")
    func undatedPresentation() throws {
        let laws = lesson("Commutative Law", order: 0)
        var input = CurriculumMapInput(lessons: [laws])
        input.presentations = [presentation(laws, on: nil)]

        let cell = try #require(cell(input, laws))
        #expect(cell.state == .presented)
        #expect(cell.firstPresented == nil)
        #expect(cell.events.isEmpty)
    }

    @Test("Work following the lesson makes it chosen; review or completion makes it repeated")
    func workClimbsTheLadder() throws {
        let laws = lesson("Commutative Law", order: 0)
        var input = CurriculumMapInput(lessons: [laws])
        input.presentations = [presentation(laws, on: "2026-02-12")]
        input.work = [work(laws, assigned: "2026-02-13")]
        #expect(try #require(cell(input, laws)).state == .chosen)

        input.work = [work(laws, status: .review, assigned: "2026-02-13")]
        #expect(try #require(cell(input, laws)).state == .repeated)
    }

    @Test("Three practice sessions are repeated; two are only chosen")
    func practiceCountsTowardRepeated() throws {
        let laws = lesson("Commutative Law", order: 0)
        let item = work(laws, assigned: "2026-02-13")
        var input = CurriculumMapInput(lessons: [laws])
        input.presentations = [presentation(laws, on: "2026-02-12")]
        input.work = [item]
        input.practice = [practice(item, on: "2026-02-14"), practice(item, on: "2026-02-15")]
        let two = try #require(cell(input, laws))
        #expect(two.state == .chosen)
        #expect(two.practiceCount == 2)

        input.practice.append(practice(item, on: "2026-02-16"))
        let three = try #require(cell(input, laws))
        #expect(three.state == .repeated)
        let practiceStates: [CurriculumCellState?] = three.events
            .filter { $0.kind == CurriculumEvent.Kind.practice }
            .map(\.state)
        let expected: [CurriculumCellState?] = [.chosen, .chosen, .repeated]
        #expect(practiceStates == expected)
    }

    @Test("A mastery record is mastered; the guide's confirmation is evidence beside the ladder")
    func masteryWins() throws {
        let laws = lesson("Commutative Law", order: 0)
        var input = CurriculumMapInput(lessons: [laws])
        input.presentations = [presentation(laws, on: "2026-02-12")]
        input.masteries = [CurriculumMasteryRef(
            id: UUID(), studentID: student, lessonID: laws.id, isMastered: true,
            presentedAt: day("2026-02-12"), masteredAt: day("2026-05-01"), lastObservedAt: nil
        )]
        let mastered = try #require(cell(input, laws))
        #expect(mastered.state == .mastered)
        #expect(mastered.lastActivity == day("2026-05-01"))

        #expect(!mastered.isConfirmed)

        input.masteries = []
        input.presentations = [presentation(laws, on: "2026-02-12", confirmed: [student])]
        let confirmed = try #require(cell(input, laws))
        #expect(confirmed.state == .presented)
        #expect(confirmed.isConfirmed)
        #expect(confirmed.events.map(\.state) == [.presented])
    }

    @Test("The latest recall check sets the ring")
    func latestRecallWins() throws {
        let laws = lesson("Commutative Law", order: 0)
        var input = CurriculumMapInput(lessons: [laws])
        input.presentations = [presentation(laws, on: "2026-02-12")]
        input.recalls = [
            CurriculumRecallRef(id: UUID(), studentID: student, lessonID: laws.id, outcome: .retained, checkedAt: day("2026-06-01")),
            CurriculumRecallRef(id: UUID(), studentID: student, lessonID: laws.id, outcome: .shaky, checkedAt: day("2026-09-01"))
        ]
        let cell = try #require(cell(input, laws))
        #expect(cell.recall == .shaky)
        #expect(cell.lastActivity == day("2026-09-01"))
    }

    @Test("A group practice on a peer's work counts for every child in the session")
    func practiceReachesLessonThroughPeerWork() throws {
        let laws = lesson("Commutative Law", order: 0)
        let peerWork = work(laws, assigned: "2026-02-13", students: [peer])
        var input = CurriculumMapInput(lessons: [laws])
        input.presentations = [presentation(laws, on: "2026-02-12", students: [student, peer])]
        input.work = [peerWork]
        input.practice = [practice(peerWork, on: "2026-02-14", students: [student, peer])]

        let cell = try #require(cell(input, laws))
        #expect(cell.state == .chosen)
        #expect(cell.evidence.workIDs.isEmpty)
        #expect(cell.evidence.practiceSessionIDs.count == 1)
    }

    @Test("Nothing recorded means no cell at all")
    func noRecordsNoCell() {
        let laws = lesson("Commutative Law", order: 0)
        let input = CurriculumMapInput(lessons: [laws])
        #expect(CurriculumMapEngine.cells(for: student, input: input).isEmpty)
    }

    // MARK: - Key Lessons & Great Lessons

    @Test("Key lessons are the hand-marked, the first of each sequence, and Great Lesson stories")
    func keyLessonFilter() {
        let first = lesson("Concept of a Multiple", order: 0)
        let marked = lesson("Distributive Law", order: 3, key: true)
        let step = lesson("Sub-step", order: 1)
        let story = lesson("The God With No Hands", area: "Geography", sequence: "Chapter 1", order: 5,
                           great: GreatLesson.comingOfUniverse.rawValue, story: true)
        let chapterFirst = lesson("Composition of the Earth", area: "Geography", sequence: "Chapter 1", order: 0)
        let all = [step, marked, first, story, chapterFirst]

        let key = CurriculumMapEngine.lessons(all, at: .keyLessons).map(\.name)
        #expect(Set(key) == ["Concept of a Multiple", "Distributive Law", "The God With No Hands", "Composition of the Earth"])
        #expect(CurriculumMapEngine.lessons(all, at: .allLessons).count == 5)
    }

    @Test("A Great Lesson is its tagged story lessons, not every lesson tagged with it")
    func greatLessonPrefersStories() {
        let story = lesson("The God With No Hands", area: "Geography", sequence: "Chapter 1", order: 0,
                           great: GreatLesson.comingOfUniverse.rawValue, story: true)
        let followUp = lesson("Volcano Demonstration", area: "Geography", sequence: "Chapter 1", order: 1,
                              great: GreatLesson.comingOfUniverse.rawValue)
        let numbers = lesson("The Story of Numerals", area: "Math", sequence: "Intro", order: 0,
                             great: GreatLesson.storyOfNumbers.rawValue)

        let byRaw = CurriculumMapEngine.greatLessonLessons(in: [followUp, story, numbers])
        #expect(byRaw[GreatLesson.comingOfUniverse.rawValue]?.map(\.name) == ["The God With No Hands"])
        #expect(byRaw[GreatLesson.storyOfNumbers.rawValue]?.map(\.name) == ["The Story of Numerals"])
        #expect(byRaw[GreatLesson.comingOfLife.rawValue] == nil)
    }

    // MARK: - Aggregates & Untouched

    @Test("An area row shows its best lesson and its latest dates")
    func aggregateTakesTheBest() throws {
        let a = lesson("A", order: 0)
        let b = lesson("B", order: 1)
        var input = CurriculumMapInput(lessons: [a, b])
        input.presentations = [presentation(a, on: "2026-01-10"), presentation(b, on: "2026-03-10")]
        input.work = [work(a, status: .mastered, assigned: "2026-01-11")]
        let cells = CurriculumMapEngine.cells(for: student, input: input)

        let summary = CurriculumMapEngine.aggregate(Array(cells.values), lessonCount: 2)
        #expect(summary.state == .repeated)
        #expect(summary.presentedCount == 2)
        #expect(summary.firstPresented == day("2026-01-10"))
        #expect(summary.lastPresented == day("2026-03-10"))
    }

    @Test("Untouched means no presentation inside the threshold, never included")
    func untouchedRule() {
        let calendar = Calendar(identifier: .gregorian)
        let today = day("2026-09-09")
        #expect(CurriculumMapEngine.isUntouched(lastPresented: nil, days: 90, today: today, calendar: calendar))
        #expect(CurriculumMapEngine.isUntouched(lastPresented: day("2026-03-01"), days: 90, today: today, calendar: calendar))
        #expect(!CurriculumMapEngine.isUntouched(lastPresented: day("2026-08-31"), days: 90, today: today, calendar: calendar))
    }

    // MARK: - Timeline

    @Test("Enrollment years count whole years from the start date")
    func enrollmentYears() {
        let calendar = Calendar(identifier: .gregorian)
        let anchor = day("2025-11-29")
        #expect(CurriculumTimeline.enrollmentYear(anchor: anchor, on: day("2026-09-09"), calendar: calendar) == 1)
        #expect(CurriculumTimeline.enrollmentYear(anchor: anchor, on: day("2026-11-28"), calendar: calendar) == 1)
        #expect(CurriculumTimeline.enrollmentYear(anchor: anchor, on: day("2026-11-29"), calendar: calendar) == 2)
        #expect(CurriculumTimeline.enrollmentYear(anchor: anchor, on: day("2028-12-01"), calendar: calendar) == 4)
        #expect(CurriculumTimeline.yearBadge(4) == "Year 3+")
        #expect(CurriculumTimeline.yearBadge(2) == "Year 2")
    }

    @Test("A three-year timeline has 36 month columns anchored on the start date")
    func timelineColumns() throws {
        let calendar = Calendar(identifier: .gregorian)
        let timeline = CurriculumTimeline.make(
            dateStarted: day("2025-11-29"), fallbackAnchor: nil, today: day("2026-09-09"),
            zoom: .months, calendar: calendar
        )
        let december: Int? = timeline.columnIndex(for: day("2025-12-15"))
        let september: Int? = timeline.columnIndex(for: day("2026-09-09"))
        let beforeStart: Int? = timeline.columnIndex(for: day("2025-11-01"))
        let ninth: CurriculumColumn = timeline.columns[9]
        let twelfth: CurriculumColumn = timeline.columns[12]
        #expect(timeline.columns.count == 36)
        #expect(timeline.currentYear == 1)
        #expect(!timeline.anchorIsEstimated)
        #expect(december == 0)
        #expect(september == 9)
        #expect(beforeStart == nil)
        #expect(ninth.year == 1)
        #expect(twelfth.year == 2)
        #expect(twelfth.isFuture)
    }

    @Test("Without a start date the timeline is anchored on the first record and says so")
    func timelineFallsBackToFirstRecord() {
        let calendar = Calendar(identifier: .gregorian)
        let timeline = CurriculumTimeline.make(
            dateStarted: nil, fallbackAnchor: day("2026-02-12"), today: day("2026-09-09"),
            zoom: .years, calendar: calendar
        )
        #expect(timeline.anchorIsEstimated)
        #expect(timeline.columns.count == 3)
        #expect(timeline.columns[0].label == "Year 1")
    }

    @Test("A child in her fourth year gets four year columns")
    func fourthYearAddsAColumn() {
        let calendar = Calendar(identifier: .gregorian)
        let timeline = CurriculumTimeline.make(
            dateStarted: day("2022-09-01"), fallbackAnchor: nil, today: day("2026-09-09"),
            zoom: .terms, calendar: calendar
        )
        #expect(timeline.currentYear == 5)
        #expect(timeline.yearCount == 5)
        #expect(timeline.columns.count == 15)
    }
}
