import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// Pins that the sidebar's single-read `sidebarInsights` gives what its
/// separate calls gave, for every timeframe.
@MainActor
struct AttendanceSidebarInsightsTests {

    private struct LCG {
        var state: UInt64
        mutating func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
    }

    @Test(arguments: AttendanceInsightsTimeframe.allCases)
    func singleReadMatchesSeparateReads(timeframe: AttendanceInsightsTimeframe) throws {
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        var rng = LCG(state: 7)
        let students = (0..<6).map { index in
            CoreDataTestHelpers.seedStudent(in: context, firstName: "Kid\(index)", lastName: "Family\(index % 2)")
        }
        let statuses: [AttendanceStatus] = [.present, .present, .present, .absent, .tardy, .leftEarly, .unmarked]
        let reasons: [AbsenceReason] = [.none, .sick, .vacation]
        let reference = try CoreDataTestHelpers.day("2026-03-18")

        for dayOffset in 0..<420 {
            let day = AppCalendar.addingDays(-dayOffset, to: reference)
            for student in students where rng.next(5) != 0 {
                let record = CDAttendanceRecord(context: context)
                record.studentID = student.cloudKitKey
                // Mostly midnight; some mid-morning stamps (outside a range whose end is that day).
                record.date = rng.next(6) == 0 ? day.addingTimeInterval(9 * 3_600) : day
                record.status = statuses[rng.next(statuses.count)]
                record.absenceReasonRaw = reasons[rng.next(reasons.count)].rawValue
                record.modifiedAt = Date(timeIntervalSince1970: 1_700_000_000 + Double(rng.next(1_000)))
                if rng.next(8) == 0 {
                    // A CloudKit-style duplicate, sometimes straddling midnight vs 9am.
                    let dup = CDAttendanceRecord(context: context)
                    dup.studentID = record.studentID
                    dup.date = rng.next(2) == 0 ? day : day.addingTimeInterval(9 * 3_600)
                    dup.status = statuses[rng.next(statuses.count)]
                    dup.modifiedAt = Date(timeIntervalSince1970: 1_700_000_000 + Double(rng.next(1_000)))
                }
            }
        }
        // A record for someone not on the roster.
        let stranger = CDAttendanceRecord(context: context)
        stranger.studentID = UUID().uuidString
        stranger.date = reference
        stranger.status = .absent
        try context.save()

        let range = timeframe.range(endingAt: reference)
        let priorRange = timeframe.priorRange(for: range)
        let insights = AttendanceInsightsService.sidebarInsights(
            range: range, priorRange: priorRange, students: students, context: context
        )

        let summary = AttendanceInsightsService.classSummary(in: range, students: students, context: context)
        let prior = AttendanceInsightsService.classSummary(in: priorRange, students: students, context: context)
        let watch = AttendanceInsightsService.watchList(in: range, students: students, context: context, limit: .max)
        // Every child on the patterns is on the separate read's list, with the same counts.
        let children = insights.patterns.flatMap(\.members)

        #expect(insights.summary == summary)
        #expect(insights.priorSummary == prior)
        #expect(children.allSatisfy { child in watch.contains(child) })

        #expect(summary.totalStudentDays > 0)
        #expect(prior.totalStudentDays > 0)
        #expect(!watch.isEmpty)
        #expect(!insights.patterns.isEmpty)
    }
}
