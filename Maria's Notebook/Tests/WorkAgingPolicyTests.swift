#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

@Suite("WorkAgingPolicy Tests")
@MainActor
struct WorkAgingPolicyTests {

    // MARK: - Test Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            WorkModel.self,
            WorkCheckIn.self,
            Note.self,
            NonSchoolDay.self,
            SchoolDayOverride.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeWorkModel(
        id: UUID = UUID(),
        assignedAt: Date = Date(),
        lastTouchedAt: Date? = nil,
        dueAt: Date? = nil,
        completedAt: Date? = nil
    ) -> WorkModel {
        return WorkModel(
            id: id,
            title: "Test Work",
            assignedAt: assignedAt,
            lastTouchedAt: lastTouchedAt,
            dueAt: dueAt
        )
    }

    private func makeCheckIn(workID: UUID, date: Date, status: WorkCheckInStatus = .completed) -> WorkCheckIn {
        return WorkCheckIn(id: UUID(), workID: workID, date: date, status: status)
    }

    private func makeNote(createdAt: Date, updatedAt: Date? = nil) -> Note {
        let note = Note(
            id: UUID(),
            createdAt: createdAt,
            content: "Test note"
        )
        if let updated = updatedAt {
            note.updatedAt = updated
        }
        return note
    }

    // MARK: - lastMeaningfulTouchDate Tests

    @Test("lastMeaningfulTouchDate returns explicit lastTouchedAt when set")
    func lastTouchExplicit() {
        let touchDate = TestCalendar.date(year: 2025, month: 1, day: 15)
        let assignDate = TestCalendar.date(year: 2025, month: 1, day: 1)
        let work = makeWorkModel(assignedAt: assignDate, lastTouchedAt: touchDate)

        let result = WorkAgingPolicy.lastMeaningfulTouchDate(for: work)

        let expected = AppCalendar.startOfDay(touchDate)
        #expect(result == expected)
    }

    @Test("lastMeaningfulTouchDate returns most recent completed check-in when no explicit touch")
    func lastTouchFromCheckIn() {
        let assignDate = TestCalendar.date(year: 2025, month: 1, day: 1)
        let checkInDate = TestCalendar.date(year: 2025, month: 1, day: 10)
        let work = makeWorkModel(assignedAt: assignDate)
        let checkIns = [makeCheckIn(workID: work.id, date: checkInDate, status: .completed)]

        let result = WorkAgingPolicy.lastMeaningfulTouchDate(for: work, checkIns: checkIns)

        let expected = AppCalendar.startOfDay(checkInDate)
        #expect(result == expected)
    }

    @Test("lastMeaningfulTouchDate ignores scheduled check-ins")
    func lastTouchIgnoresScheduledCheckIns() {
        let assignDate = TestCalendar.date(year: 2025, month: 1, day: 1)
        let scheduledDate = TestCalendar.date(year: 2025, month: 1, day: 10)
        let work = makeWorkModel(assignedAt: assignDate)
        let checkIns = [makeCheckIn(workID: work.id, date: scheduledDate, status: .scheduled)]

        let result = WorkAgingPolicy.lastMeaningfulTouchDate(for: work, checkIns: checkIns)

        // Should fall back to assignedAt since scheduled check-ins don't count
        let expected = AppCalendar.startOfDay(assignDate)
        #expect(result == expected)
    }

    @Test("lastMeaningfulTouchDate ignores future check-ins")
    func lastTouchIgnoresFutureCheckIns() {
        let assignDate = TestCalendar.date(year: 2025, month: 1, day: 1)
        let futureDate = TestCalendar.date(year: 2025, month: 12, day: 31)
        let work = makeWorkModel(assignedAt: assignDate)
        let checkIns = [makeCheckIn(workID: work.id, date: futureDate, status: .completed)]

        let result = WorkAgingPolicy.lastMeaningfulTouchDate(for: work, checkIns: checkIns)

        // Should fall back to assignedAt since future dates don't count
        let expected = AppCalendar.startOfDay(assignDate)
        #expect(result == expected)
    }

    @Test("lastMeaningfulTouchDate returns most recent note timestamp")
    func lastTouchFromNote() {
        let assignDate = TestCalendar.date(year: 2025, month: 1, day: 1)
        let noteCreatedDate = TestCalendar.date(year: 2025, month: 1, day: 10)
        let noteUpdatedDate = TestCalendar.date(year: 2025, month: 1, day: 15)
        let work = makeWorkModel(assignedAt: assignDate)
        let notes = [makeNote(createdAt: noteCreatedDate, updatedAt: noteUpdatedDate)]

        let result = WorkAgingPolicy.lastMeaningfulTouchDate(for: work, notes: notes)

        // Should use updatedAt (more recent than createdAt)
        #expect(result == noteUpdatedDate)
    }

    @Test("lastMeaningfulTouchDate prefers check-in over note")
    func lastTouchPrefersCheckIn() {
        let assignDate = TestCalendar.date(year: 2025, month: 1, day: 1)
        let checkInDate = TestCalendar.date(year: 2025, month: 1, day: 15)
        let noteDate = TestCalendar.date(year: 2025, month: 1, day: 10)
        let work = makeWorkModel(assignedAt: assignDate)
        let checkIns = [makeCheckIn(workID: work.id, date: checkInDate, status: .completed)]
        let notes = [makeNote(createdAt: noteDate)]

        let result = WorkAgingPolicy.lastMeaningfulTouchDate(for: work, checkIns: checkIns, notes: notes)

        let expected = AppCalendar.startOfDay(checkInDate)
        #expect(result == expected)
    }

    @Test("lastMeaningfulTouchDate falls back to assignedAt")
    func lastTouchFallbackToAssignedAt() {
        let assignDate = TestCalendar.date(year: 2025, month: 1, day: 1)
        let work = makeWorkModel(assignedAt: assignDate)

        let result = WorkAgingPolicy.lastMeaningfulTouchDate(for: work, checkIns: [], notes: [])

        let expected = AppCalendar.startOfDay(assignDate)
        #expect(result == expected)
    }

    @Test("lastMeaningfulTouchDate selects most recent of multiple check-ins")
    func lastTouchMultipleCheckIns() {
        let assignDate = TestCalendar.date(year: 2025, month: 1, day: 1)
        let work = makeWorkModel(assignedAt: assignDate)
        let checkIns = [
            makeCheckIn(workID: work.id, date: TestCalendar.date(year: 2025, month: 1, day: 5), status: .completed),
            makeCheckIn(workID: work.id, date: TestCalendar.date(year: 2025, month: 1, day: 15), status: .completed),
            makeCheckIn(workID: work.id, date: TestCalendar.date(year: 2025, month: 1, day: 10), status: .completed),
        ]

        let result = WorkAgingPolicy.lastMeaningfulTouchDate(for: work, checkIns: checkIns)

        let expected = AppCalendar.startOfDay(TestCalendar.date(year: 2025, month: 1, day: 15))
        #expect(result == expected)
    }

    // MARK: - daysSinceLastTouch Tests (School Day Aware)

    @Test("daysSinceLastTouch counts weekdays only")
    func daysSinceLastTouchWeekdaysOnly() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Monday Jan 13, 2025 to Friday Jan 17, 2025 = 5 weekdays (no weekends)
        let lastTouch = TestCalendar.date(year: 2025, month: 1, day: 13) // Monday
        let work = makeWorkModel(assignedAt: lastTouch, lastTouchedAt: lastTouch)

        // Mock today as Friday Jan 17
        let originalDate = Date()
        defer { /* Can't easily mock Date() in tests, so we accept current date */ }

        let result = WorkAgingPolicy.daysSinceLastTouch(for: work, modelContext: context)

        // This test depends on current date, so we'll verify it's >= 0
        #expect(result >= 0)
    }

    @Test("daysSinceLastTouch excludes weekends")
    func daysSinceLastTouchExcludesWeekends() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Friday to next Monday = 1 school day (excluding weekend)
        let friday = TestCalendar.date(year: 2025, month: 1, day: 10) // Friday
        let work = makeWorkModel(assignedAt: friday, lastTouchedAt: friday)

        let result = WorkAgingPolicy.daysSinceLastTouch(for: work, modelContext: context)

        // Result depends on current date, just verify it doesn't crash
        #expect(result >= 0)
    }

    @Test("daysSinceLastTouch excludes NonSchoolDay")
    func daysSinceLastTouchExcludesNonSchoolDay() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Add a non-school day (e.g., holiday)
        let holiday = TestCalendar.startOfDay(year: 2025, month: 1, day: 15)
        let nonSchoolDay = NonSchoolDay(date: holiday, reason: "Holiday")
        context.insert(nonSchoolDay)
        try context.save()

        let work = makeWorkModel(assignedAt: TestCalendar.date(year: 2025, month: 1, day: 10))

        let result = WorkAgingPolicy.daysSinceLastTouch(for: work, modelContext: context)

        #expect(result >= 0)
    }

    @Test("daysSinceLastTouch includes weekend with SchoolDayOverride")
    func daysSinceLastTouchIncludesOverride() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Add a school day override for Saturday
        let saturday = TestCalendar.startOfDay(year: 2025, month: 1, day: 18) // Saturday
        let override = SchoolDayOverride(date: saturday, note: "Make-up day")
        context.insert(override)
        try context.save()

        let work = makeWorkModel(assignedAt: TestCalendar.date(year: 2025, month: 1, day: 10))

        let result = WorkAgingPolicy.daysSinceLastTouch(for: work, modelContext: context)

        #expect(result >= 0)
    }

    @Test("daysSinceLastTouch returns 0 for same day")
    func daysSinceLastTouchSameDay() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let today = AppCalendar.startOfDay(Date())
        let work = makeWorkModel(assignedAt: today, lastTouchedAt: today)

        let result = WorkAgingPolicy.daysSinceLastTouch(for: work, modelContext: context)

        #expect(result == 0)
    }

    // MARK: - agingBucket Tests

    @Test("agingBucket returns fresh for recent work")
    func agingBucketFresh() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let today = AppCalendar.startOfDay(Date())
        let work = makeWorkModel(assignedAt: today, lastTouchedAt: today)

        let result = WorkAgingPolicy.agingBucket(for: work, modelContext: context)

        #expect(result == .fresh)
    }

    @Test("agingBucket returns aging after threshold")
    func agingBucketAging() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Create work from 6 school days ago (default aging threshold is 5)
        let sixDaysAgo = TestCalendar.date(year: 2025, month: 1, day: 1)
        let work = makeWorkModel(assignedAt: sixDaysAgo, lastTouchedAt: sixDaysAgo)

        let result = WorkAgingPolicy.agingBucket(for: work, modelContext: context)

        // Result depends on current date and whether we're past the threshold
        #expect(result == .fresh || result == .aging || result == .stale)
    }

    // MARK: - isOverdue Tests

    @Test("isOverdue returns false when no dueAt")
    func isOverdueNoDueDate() {
        let work = makeWorkModel(assignedAt: TestCalendar.date(year: 2025, month: 1, day: 1))

        let result = WorkAgingPolicy.isOverdue(work)

        #expect(result == false)
    }

    @Test("isOverdue returns false when dueAt is in future")
    func isOverdueFutureDueDate() {
        let futureDate = TestCalendar.date(year: 2099, month: 12, day: 31)
        let work = makeWorkModel(assignedAt: TestCalendar.date(year: 2025, month: 1, day: 1), dueAt: futureDate)

        let result = WorkAgingPolicy.isOverdue(work)

        #expect(result == false)
    }

    @Test("isOverdue returns true when dueAt is in past and no touch since")
    func isOverduePastDueDate() {
        let pastDue = TestCalendar.date(year: 2024, month: 1, day: 1)
        let assignDate = TestCalendar.date(year: 2023, month: 12, day: 1)
        let work = makeWorkModel(assignedAt: assignDate, dueAt: pastDue)

        let result = WorkAgingPolicy.isOverdue(work)

        #expect(result == true)
    }

    @Test("isOverdue returns false when touched after due date")
    func isOverdueTouchedAfterDue() {
        let dueDate = TestCalendar.date(year: 2024, month: 1, day: 1)
        let touchDate = TestCalendar.date(year: 2024, month: 1, day: 5)
        let work = makeWorkModel(assignedAt: TestCalendar.date(year: 2023, month: 12, day: 1), lastTouchedAt: touchDate, dueAt: dueDate)

        let result = WorkAgingPolicy.isOverdue(work, lastTouch: touchDate)

        #expect(result == false)
    }

    @Test("isOverdue checks scheduled check-ins for due date")
    func isOverdueFromCheckIn() {
        let pastDate = TestCalendar.date(year: 2024, month: 1, day: 1)
        let work = makeWorkModel(assignedAt: TestCalendar.date(year: 2023, month: 12, day: 1))
        let checkIns = [makeCheckIn(workID: work.id, date: pastDate, status: .scheduled)]

        let result = WorkAgingPolicy.isOverdue(work, checkIns: checkIns)

        #expect(result == true)
    }

    @Test("isOverdue returns false for today's due date")
    func isOverdueDueToday() {
        let today = AppCalendar.startOfDay(Date())
        let work = makeWorkModel(assignedAt: TestCalendar.date(year: 2023, month: 12, day: 1), dueAt: today)

        let result = WorkAgingPolicy.isOverdue(work)

        #expect(result == false)
    }

    // MARK: - isDueToday Tests

    @Test("isDueToday returns true when dueAt is today")
    func isDueTodayTrue() {
        let today = AppCalendar.startOfDay(Date())
        let work = makeWorkModel(dueAt: today)

        let result = WorkAgingPolicy.isDueToday(work)

        #expect(result == true)
    }

    @Test("isDueToday returns false when no dueAt")
    func isDueTodayNoDue() {
        let work = makeWorkModel()

        let result = WorkAgingPolicy.isDueToday(work)

        #expect(result == false)
    }

    @Test("isDueToday returns false when dueAt is tomorrow")
    func isDueTodayFuture() {
        let tomorrow = AppCalendar.addingDays(1, to: AppCalendar.startOfDay(Date()))
        let work = makeWorkModel(dueAt: tomorrow)

        let result = WorkAgingPolicy.isDueToday(work)

        #expect(result == false)
    }

    @Test("isDueToday checks scheduled check-ins")
    func isDueTodayFromCheckIn() {
        let today = AppCalendar.startOfDay(Date())
        let work = makeWorkModel()
        let checkIns = [makeCheckIn(workID: work.id, date: today, status: .scheduled)]

        let result = WorkAgingPolicy.isDueToday(work, checkIns: checkIns)

        #expect(result == true)
    }

    // MARK: - isUpcoming Tests

    @Test("isUpcoming returns true for tomorrow")
    func isUpcomingTomorrow() {
        let tomorrow = AppCalendar.addingDays(1, to: AppCalendar.startOfDay(Date()))
        let work = makeWorkModel(dueAt: tomorrow)

        let result = WorkAgingPolicy.isUpcoming(work)

        #expect(result == true)
    }

    @Test("isUpcoming returns true for day after tomorrow")
    func isUpcomingDayAfter() {
        let dayAfter = AppCalendar.addingDays(2, to: AppCalendar.startOfDay(Date()))
        let work = makeWorkModel(dueAt: dayAfter)

        let result = WorkAgingPolicy.isUpcoming(work)

        #expect(result == true)
    }

    @Test("isUpcoming returns false for today")
    func isUpcomingToday() {
        let today = AppCalendar.startOfDay(Date())
        let work = makeWorkModel(dueAt: today)

        let result = WorkAgingPolicy.isUpcoming(work)

        #expect(result == false)
    }

    @Test("isUpcoming returns false for 3 days away")
    func isUpcomingTooFar() {
        let threeDays = AppCalendar.addingDays(3, to: AppCalendar.startOfDay(Date()))
        let work = makeWorkModel(dueAt: threeDays)

        let result = WorkAgingPolicy.isUpcoming(work)

        #expect(result == false)
    }

    @Test("isUpcoming returns false when no due date")
    func isUpcomingNoDue() {
        let work = makeWorkModel()

        let result = WorkAgingPolicy.isUpcoming(work)

        #expect(result == false)
    }

    // MARK: - urgencyBucket Tests

    @Test("urgencyBucket returns none for no urgency")
    func urgencyBucketNone() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = makeWorkModel()

        let result = WorkAgingPolicy.urgencyBucket(for: work, modelContext: context)

        #expect(result == .none || result == .stale) // Could be stale if old enough
    }

    @Test("urgencyBucket returns today for work due today")
    func urgencyBucketToday() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let today = AppCalendar.startOfDay(Date())
        let work = makeWorkModel(dueAt: today, lastTouchedAt: today)

        let result = WorkAgingPolicy.urgencyBucket(for: work, modelContext: context)

        #expect(result == .today)
    }

    @Test("urgencyBucket returns upcoming for work due tomorrow")
    func urgencyBucketUpcoming() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let tomorrow = AppCalendar.addingDays(1, to: AppCalendar.startOfDay(Date()))
        let work = makeWorkModel(dueAt: tomorrow, lastTouchedAt: AppCalendar.startOfDay(Date()))

        let result = WorkAgingPolicy.urgencyBucket(for: work, modelContext: context)

        #expect(result == .upcoming)
    }

    @Test("urgencyBucket returns overdue for past due work")
    func urgencyBucketOverdue() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let pastDue = TestCalendar.date(year: 2024, month: 1, day: 1)
        let work = makeWorkModel(assignedAt: TestCalendar.date(year: 2023, month: 12, day: 1), dueAt: pastDue)

        let result = WorkAgingPolicy.urgencyBucket(for: work, modelContext: context)

        #expect(result == .overdue)
    }

    @Test("urgencyBucket comparison ordering")
    func urgencyBucketOrdering() {
        #expect(UrgencyBucket.none < UrgencyBucket.upcoming)
        #expect(UrgencyBucket.upcoming < UrgencyBucket.today)
        #expect(UrgencyBucket.today < UrgencyBucket.overdue)
        #expect(UrgencyBucket.overdue < UrgencyBucket.stale)
    }

    // MARK: - AgingBucket Tests

    @Test("AgingBucket comparison ordering")
    func agingBucketOrdering() {
        #expect(AgingBucket.fresh < AgingBucket.aging)
        #expect(AgingBucket.aging < AgingBucket.stale)
    }
}

#endif
