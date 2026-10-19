import Foundation
import Testing
@testable import CosmicDaybook

// The review findings on the 2026-10-12 curriculum-map fixes: a child who
// started just before the configured school-year start belongs to that year,
// not the one before (#34).

@Suite("Curriculum map fixes 2026-10-12: review")
struct CurriculumMapFix1012Review {

    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: iso)!
    }

    private func year(started: String, on date: String) -> Int {
        CurriculumTimeline.enrollmentYear(
            anchor: day(started), on: day(date), startMonth: 8, startDay: 25, calendar: calendar
        )
    }

    private func timeline(started: String, today: String = "2026-10-12") -> CurriculumTimeline {
        CurriculumTimeline.make(
            dateStarted: day(started), fallbackAnchor: nil, today: day(today),
            zoom: .years, startMonth: 8, startDay: 25, calendar: calendar
        )
    }

    // MARK: - #34 A start just before the school year counts as that year

    @Test("A start one day before the school-year start counts as that school year")
    func dayBeforeStartCountsAsThatYear() {
        #expect(year(started: "2025-08-24", on: "2025-08-24") == 1)
        #expect(year(started: "2025-08-24", on: "2025-09-01") == 1)
        #expect(year(started: "2025-08-24", on: "2026-08-24") == 1)
        #expect(year(started: "2025-08-24", on: "2026-10-12") == 2)

        let timeline = timeline(started: "2025-08-24")
        #expect(timeline.currentYear == 2)
        #expect(timeline.columns[0].year == 1)
        #expect(timeline.columns[0].contains(day("2025-09-01")))
        #expect(!timeline.columns[0].contains(day("2024-09-01")))
        #expect(timeline.columns[1].start == day("2026-08-25"))
        // Her first day is still drawn, in her first year.
        #expect(timeline.columnIndex(for: day("2025-08-24")) == 0)
    }

    @Test("A start on the school-year start is that school year")
    func startOnTheStart() {
        #expect(year(started: "2025-08-25", on: "2026-08-24") == 1)
        #expect(year(started: "2025-08-25", on: "2026-10-12") == 2)
        let timeline = timeline(started: "2025-08-25")
        #expect(timeline.currentYear == 2)
        #expect(timeline.columns[0].start == day("2025-08-25"))
        #expect(timeline.columns[1].start == day("2026-08-25"))
    }

    @Test("A mid-year start is the school year it falls in")
    func midYearStart() {
        #expect(year(started: "2026-01-05", on: "2026-08-24") == 1)
        #expect(year(started: "2026-01-05", on: "2026-10-12") == 2)
        let timeline = timeline(started: "2026-01-05")
        #expect(timeline.columns[0].start == day("2025-08-25"))
    }

    @Test("Thirty days before the start counts as that year; thirty-one does not")
    func thirtyDayWindow() {
        #expect(year(started: "2025-07-26", on: "2026-10-12") == 2)
        #expect(year(started: "2025-07-25", on: "2026-10-12") == 3)
        #expect(timeline(started: "2025-07-25").columns[0].start == day("2024-08-25"))
    }
}

// A genuinely shared row (project work: one row, several children) counts for
// everyone on it, even beside a row of her own on the same lesson (#30).
@Suite("Curriculum map fixes 2026-10-12: review, shared rows")
@MainActor
struct CurriculumMapFix1012ReviewShared {

    @Test("Her own Working row beside a Complete shared project row reads Practicing (her open work wins, as on the Checklist), and the sheet lists both")
    func sharedProjectRowBesideHerOwn() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = UUID()
        let eli = UUID()
        let lessonID = UUID()
        let hers = CoreDataTestHelpers.seedWorkModel(in: context, studentID: maya, lessonID: lessonID)
        hers.statusRaw = WorkStatus.active.rawValue
        let project = CoreDataTestHelpers.seedWorkModel(in: context, studentID: eli, lessonID: lessonID)
        project.statusRaw = WorkStatus.done.rawValue
        project.sourceContextType = .projectSession
        for student in [eli, maya] {
            let participant = CDWorkParticipantEntity(context: context)
            participant.studentID = student.uuidString
            participant.work = project
        }
        #expect(CoreDataTestHelpers.save(context))
        let hersID = try #require(hers.id)
        let projectID = try #require(project.id)

        let input = CurriculumMapLoader.snapshot(in: context)
        let cell = try #require(ClassGridEngine.cells(for: maya, input: input)[lessonID])
        #expect(cell.state == .practicing)
        #expect(Set(cell.evidence.workIDs) == [hersID, projectID])

        let sheet = ClassGridEngine.ownWork(for: maya, among: input.work)
        #expect(Set(sheet.map(\.id)) == [hersID, projectID])
        // Eli sees the project row and nothing of hers.
        #expect(ClassGridEngine.ownWork(for: eli, among: input.work).map(\.id) == [projectID])
    }
}

// Both maps redraw by the school-year start they are given, so a change to
// the setting reaches them (#33).
@Suite("Curriculum map fixes 2026-10-12: review, school-year start")
@MainActor
struct CurriculumMapFix1012ReviewSchoolYearStart {

    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: iso)!
    }

    private func loadedStore(started: String) async throws -> (store: CurriculumMapStore, studentID: UUID) {
        let context = try CoreDataTestHelpers.makeContext()
        let student = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Maya", lastName: "Sloane", dateStarted: day(started)
        )
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "The Cell", area: "Biology", sequence: "Life")
        lesson.isKeyLesson = true
        #expect(CoreDataTestHelpers.save(context))
        let store = CurriculumMapStore()
        await store.load(from: context)
        return (store, try #require(student.id))
    }

    @Test("The child's grid follows the school-year start it is given")
    func studentGridFollowsStart() async throws {
        let (store, studentID) = try await loadedStore(started: "2025-09-01")
        let model = StudentCurriculumMapModel()
        func firstColumnStart(month: Int, startDay: Int) -> Date? {
            model.rebuild(
                studentID: studentID, store: store, settings: CurriculumMapSettings(), zoom: .years,
                granularity: .keyLessons, startMonth: month, startDay: startDay,
                today: day("2026-10-12"), calendar: calendar
            )
            return model.timeline?.columns.first?.start
        }
        #expect(firstColumnStart(month: 9, startDay: 1) == day("2025-09-01"))
        #expect(firstColumnStart(month: 8, startDay: 25) == day("2025-08-25"))
    }

    @Test("The class map's Year N follows the school-year start it is given")
    func classYearFollowsStart() async throws {
        let (store, studentID) = try await loadedStore(started: "2025-07-01")
        let model = ClassGridYearsModel()
        func year(month: Int, startDay: Int) -> Int? {
            model.rebuild(
                store: store, area: nil, sequence: nil, granularity: .keyLessons, stateFilter: nil,
                startMonth: month, startDay: startDay, today: day("2026-10-12"), calendar: calendar
            )
            return model.columns.first { $0.student.id == studentID }?.year
        }
        #expect(year(month: 8, startDay: 1) == 3)
        #expect(year(month: 7, startDay: 1) == 2)
    }
}
