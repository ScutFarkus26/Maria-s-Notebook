import Foundation
import Testing
@testable import CosmicDaybook

// The 2026-10-12 bug hunt's curriculum-map findings, pinned on value types:
// a classmate's linked copy of work is not the child's own (#30), a checklist
// mark's stamped date is not a presentation date when the cell has
// presentation rows (#31), month and term columns leave no gap when the year
// starts on the 29th–31st (#33), and "Year N" counts school years (#34).

@Suite("Curriculum map fixes 2026-10-12")
struct CurriculumMapFix1012CM {

    // MARK: - Fixtures

    private let maya = UUID()
    private let eli = UUID()
    private let ana = UUID()
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: iso)!
    }

    private func lesson(_ name: String, order: Int = 0) -> CurriculumLessonRef {
        CurriculumLessonRef(
            id: UUID(), name: name, area: "Math", sequence: "Laws", section: "", orderInSequence: order,
            sortIndex: order, greatLessonRaw: nil, isStory: false, isKeyLesson: false
        )
    }

    private func work(
        _ lesson: CurriculumLessonRef, owner: UUID?, students: [UUID], status: WorkStatus = .active
    ) -> CurriculumWorkRef {
        CurriculumWorkRef(
            id: UUID(), lessonID: lesson.id, studentIDs: students, statusRaw: status.rawValue,
            assignedAt: day("2026-09-14"), completedAt: status.isClosed ? day("2026-09-20") : nil,
            lastTouchedAt: nil, ownerID: owner
        )
    }

    // MARK: - #30 Linked copies count only for their owner

    @Test("A classmate's Mastered linked copy doesn't make her cell Repeated")
    func classmateCopyIsNotHers() throws {
        let laws = lesson("Commutative Law")
        let group = [maya, eli, ana]
        let hers = work(laws, owner: maya, students: group)
        let elis = work(laws, owner: eli, students: group, status: .mastered)
        let anas = work(laws, owner: ana, students: group)
        var input = CurriculumMapInput(lessons: [laws])
        input.work = [hers, elis, anas]

        let mine = try #require(CurriculumMapEngine.cells(for: maya, input: input)[laws.id])
        #expect(mine.state == .chosen)
        #expect(mine.evidence.workIDs == [hers.id])

        let whole = try #require(CurriculumMapEngine.cells(input: input)[eli]?[laws.id])
        #expect(whole.state == .repeated)
        #expect(whole.evidence.workIDs == [elis.id])

        let scoped = try #require(CurriculumMapEngine.cells(input: input, lessons: [laws.id])[maya]?[laws.id])
        #expect(scoped.evidence.workIDs == [hers.id])
    }

    @Test("A shared row still counts for a child who owns nothing on the lesson")
    func sharedRowCountsForParticipants() throws {
        let laws = lesson("Commutative Law")
        let shared = work(laws, owner: eli, students: [eli, maya], status: .mastered)
        var input = CurriculumMapInput(lessons: [laws])
        input.work = [shared]

        let mine = try #require(CurriculumMapEngine.cells(for: maya, input: input)[laws.id])
        #expect(mine.state == .repeated)
        #expect(mine.evidence.workIDs == [shared.id])
    }

    @Test("The cell sheet keeps her own rows, lesson by lesson")
    func ownWorkPerLesson() {
        let laws = lesson("Commutative Law", order: 0)
        let squares = lesson("Squares", order: 1)
        let group = [maya, eli]
        let hers = work(laws, owner: maya, students: group)
        let elisLaws = work(laws, owner: eli, students: group)
        let elisSquares = work(squares, owner: eli, students: group)
        let unrelated = work(squares, owner: ana, students: [ana])

        let shown = CurriculumMapEngine.ownWork(for: maya, among: [hers, elisLaws, elisSquares, unrelated])
        #expect(shown.map(\.id) == [hers.id, elisSquares.id])
    }

    // MARK: - #31 A stamped checklist date is not a presentation date

    @Test("An undated presentation row keeps the mastery record's stamped date out")
    func stampedDateIgnoredWithPresentationRows() throws {
        let laws = lesson("Commutative Law")
        var input = CurriculumMapInput(lessons: [laws])
        input.presentations = [CurriculumPresentationRef(
            id: UUID(), lessonID: laws.id, studentIDs: [maya], presentedAt: nil, confirmedStudentIDs: []
        )]
        input.masteries = [CurriculumMasteryRef(
            id: UUID(), studentID: maya, lessonID: laws.id, isMastered: false,
            presentedAt: day("2026-10-12"), masteredAt: nil, lastObservedAt: nil
        )]

        let cell = try #require(CurriculumMapEngine.cells(for: maya, input: input)[laws.id])
        #expect(cell.state == .presented)
        #expect(cell.firstPresented == nil)
        #expect(cell.lastPresented == nil)
    }

    @Test("With no presentation rows at all, the mastery record's date still counts")
    func recordDateUsedAlone() throws {
        let laws = lesson("Commutative Law")
        var input = CurriculumMapInput(lessons: [laws])
        input.masteries = [CurriculumMasteryRef(
            id: UUID(), studentID: maya, lessonID: laws.id, isMastered: false,
            presentedAt: day("2026-03-02"), masteredAt: nil, lastObservedAt: nil
        )]

        let cell = try #require(CurriculumMapEngine.cells(for: maya, input: input)[laws.id])
        #expect(cell.firstPresented == day("2026-03-02"))
    }

    // MARK: - #33 Columns leave no gap

    @Test("Month columns from a start on the 31st cover every day")
    func monthColumnsAreContiguous() throws {
        let timeline = CurriculumTimeline.make(
            dateStarted: day("2026-01-31"), fallbackAnchor: nil, today: day("2026-03-01"),
            zoom: .months, startMonth: 1, startDay: 31, calendar: calendar
        )
        for (left, right) in zip(timeline.columns, timeline.columns.dropFirst()) {
            #expect(left.end == right.start)
        }
        let lateMarch: Int? = timeline.columnIndex(for: day("2026-03-29"))
        #expect(lateMarch != nil)
    }

    @Test("Term and month columns of a year starting August 31 cover every day")
    func columnsContiguousForLateStartDay() {
        for zoom in [CurriculumZoom.months, .terms] {
            let timeline = CurriculumTimeline.make(
                dateStarted: day("2025-08-31"), fallbackAnchor: nil, today: day("2026-03-01"),
                zoom: zoom, startMonth: 8, startDay: 31, calendar: calendar
            )
            for (left, right) in zip(timeline.columns, timeline.columns.dropFirst()) {
                #expect(left.end == right.start)
            }
        }
    }

    // MARK: - #34 Year N counts school years

    @Test("A child who joined in January is in her second year from the next school-year start")
    func yearCountsSchoolYears() {
        let joined = day("2026-01-05")
        func year(_ iso: String) -> Int {
            CurriculumTimeline.enrollmentYear(
                anchor: joined, on: day(iso), startMonth: 8, startDay: 25, calendar: calendar
            )
        }
        #expect(year("2026-01-05") == 1)
        #expect(year("2026-08-24") == 1)
        #expect(year("2026-08-25") == 2)
        #expect(year("2027-01-04") == 2)
        #expect(year("2027-08-25") == 3)
    }

    @Test("The timeline's years are school years, and her start date is kept")
    func timelineYearsAreSchoolYears() {
        let timeline = CurriculumTimeline.make(
            dateStarted: day("2026-01-05"), fallbackAnchor: nil, today: day("2026-09-09"),
            zoom: .years, startMonth: 8, startDay: 25, calendar: calendar
        )
        #expect(timeline.currentYear == 2)
        #expect(timeline.anchor == day("2026-01-05"))
        #expect(timeline.columns.count == 3)
        #expect(timeline.columns[0].start == day("2025-08-25"))
        #expect(timeline.columns[1].start == day("2026-08-25"))
        #expect(timeline.columns[1].contains(day("2026-09-09")))
        #expect(timeline.columns[1].label == "Year 2")
    }
}

// The same linked copies read through the loader from Core Data: each row's
// owner travels with it, so the engine can keep a child's own copy.
@Suite("Curriculum map fixes 2026-10-12: loader")
@MainActor
struct CurriculumMapFix1012CMLoader {

    @Test("Loaded linked copies count only for their owners")
    func loadedLinkedCopies() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = UUID()
        let eli = UUID()
        let lessonID = UUID()
        func copy(owner: UUID, status: WorkStatus) -> CDWorkModel {
            let work = CoreDataTestHelpers.seedWorkModel(in: context, studentID: owner, lessonID: lessonID)
            work.statusRaw = status.rawValue
            for student in [maya, eli] {
                let participant = CDWorkParticipantEntity(context: context)
                participant.studentID = student.uuidString
                participant.work = work
            }
            return work
        }
        let hers = copy(owner: maya, status: .active)
        let elis = copy(owner: eli, status: .mastered)
        #expect(CoreDataTestHelpers.save(context))
        let hersID = try #require(hers.id)
        let elisID = try #require(elis.id)

        let input = CurriculumMapLoader.snapshot(in: context)
        let refs = Dictionary(uniqueKeysWithValues: input.work.map { ($0.id, $0) })
        #expect(refs[hersID]?.ownerID == maya)
        #expect(refs[elisID]?.ownerID == eli)

        let mine = try #require(CurriculumMapEngine.cells(for: maya, input: input)[lessonID])
        #expect(mine.state == .chosen)
        #expect(mine.evidence.workIDs == [hersID])
        let his = try #require(CurriculumMapEngine.cells(for: eli, input: input)[lessonID])
        #expect(his.state == .repeated)
    }
}
