import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

// Logic-break sweep 2026-09-29, E4. Today fetched only open work created in
// the last 90 days, so a child's longest-open work dropped off it, and it
// counted every attendance record of the day, duplicates included.
@Suite("Today data fetcher")
@MainActor
struct TodayDataFetcherTests {

    @Test("Open work shows however long ago it was made")
    func oldOpenWork() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let old = CoreDataTestHelpers.seedWorkModel(in: context, title: "Long division")
        old.id = UUID()
        old.status = .active
        old.createdAt = AppCalendar.addingDays(-200, to: Date())
        let closed = CoreDataTestHelpers.seedWorkModel(in: context, title: "Done")
        closed.id = UUID()
        closed.status = .mastered
        CoreDataTestHelpers.save(context)

        let (day, next) = AppCalendar.dayRange(for: Date())
        let fetch = try #require(
            TodayDataFetcher.fetchWorkData(day: day, nextDay: next, referenceDate: day, context: context)
        )
        #expect(fetch.workItems.map(\.title) == ["Long division"])
    }

    @Test("A child marked on two devices counts once")
    func attendanceDeduplicated() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let (day, next) = AppCalendar.dayRange(for: Date())
        let maya = UUID()
        let first = CoreDataTestHelpers.seedAttendance(in: context, studentID: maya, date: day)
        first.status = .present
        first.modifiedAt = day
        let second = CoreDataTestHelpers.seedAttendance(in: context, studentID: maya, date: day)
        second.status = .tardy
        second.modifiedAt = day.addingTimeInterval(60)
        CoreDataTestHelpers.seedAttendance(in: context, date: day).status = .absent
        CoreDataTestHelpers.save(context)

        let result = TodayDataFetcher.fetchAttendance(day: day, nextDay: next, context: context)
        #expect(result.records.count == 2)
        #expect(result.records.first { $0.studentID == maya.uuidString }?.status == .tardy)
    }
}
