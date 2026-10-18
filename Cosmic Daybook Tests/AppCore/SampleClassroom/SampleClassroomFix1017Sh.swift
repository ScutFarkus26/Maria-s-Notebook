// Bug hunt 2026-10-17 #38: the Sample Class seeded attendance on weekends and
// scheduled its sample plans on days off.

import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("Sample Class school days (Fix1017Sh)", .serialized)
@MainActor
struct SampleClassroomFix1017ShTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }()

    /// Mid-morning on 2026-10-`day` (the 17th and 18th are a Saturday and Sunday).
    private func october(_ day: Int) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 10)))
    }

    private func startsOfDay(_ days: [Int]) throws -> Set<Date> {
        Set(try days.map { calendar.startOfDay(for: try october($0)) })
    }

    @Test("Sample attendance covers the last five school days")
    func attendanceSkipsWeekends() throws {
        let primary = try CoreDataTestHelpers.makeInMemoryStack()
        let sample = try CoreDataTestHelpers.makeInMemoryStack()

        try SampleClassroomSeeder.prepare(
            lessonsFrom: primary.viewContext,
            sampleContext: sample.viewContext,
            now: try october(19),
            calendar: calendar
        )

        let records = try sample.viewContext.fetch(CDFetchRequest(CDAttendanceRecord.self))
        let days = Set(records.compactMap { $0.date.map { calendar.startOfDay(for: $0) } })
        #expect(days == (try startsOfDay([19, 16, 15, 14, 13])))
        #expect(records.count == 5 * 9)
    }

    @Test("Sample plans are scheduled on school days")
    func plansSkipWeekends() throws {
        let primary = try CoreDataTestHelpers.makeInMemoryStack()
        let sample = try CoreDataTestHelpers.makeInMemoryStack()
        for index in 0..<5 {
            _ = CoreDataTestHelpers.seedLesson(in: primary.viewContext, name: "Lesson \(index)")
        }
        try primary.viewContext.save()

        try SampleClassroomSeeder.prepare(
            lessonsFrom: primary.viewContext,
            sampleContext: sample.viewContext,
            now: try october(16),
            calendar: calendar
        )

        let assignments = try sample.viewContext.fetch(CDFetchRequest(CDLessonAssignment.self))
        let scheduledDays = assignments.compactMap(\.scheduledFor).map { calendar.startOfDay(for: $0) }
        #expect(scheduledDays.count == 3)
        #expect(Set(scheduledDays) == (try startsOfDay([16, 19, 20])))
    }
}
