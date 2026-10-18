import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-17, #5, #6 and #7: an absence reason outlived the
/// absence; the Mac's Insights counted only the children enrolled on the day
/// on screen, test students included; Left Early played an arrival's bell,
/// sparkles and wave; and a Feb 29 birthday fell on Feb 28 on the tile but
/// Mar 1 on the roster.
@Suite("Attendance (Fix1017 At)")
@MainActor
struct AttendanceFix1017AtTests {

    private let context: NSManagedObjectContext

    init() throws {
        context = try CoreDataTestHelpers.makeContext()
    }

    // MARK: - #5

    @Test("A reason goes when the mark leaves absent, whichever mark it goes to")
    func reasonClearsWhenLeavingAbsent() throws {
        let store = CDAttendanceStore(context: context, role: .leadGuide)
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        let record = try #require(try store.ensureRecord(for: maya, on: try CoreDataTestHelpers.day("2026-10-13")))

        for next in [AttendanceStatus.present, .tardy, .leftEarly, .unmarked] {
            #expect(store.updateStatus(record, to: .absent) || record.status == .absent)
            #expect(store.updateAbsenceReason(record, to: .vacation))
            if next == .unmarked {
                #expect(store.unmark(record))
            } else {
                #expect(store.updateStatus(record, to: next))
            }
            #expect(record.absenceReasonRaw == AbsenceReason.none.rawValue, "after \(next)")
        }
        // A later plain Absent has no reason.
        #expect(store.updateStatus(record, to: .absent))
        #expect(record.absenceReason == .none)
    }

    @Test("A reason left on a record that isn't absent doesn't come back on a later Absent")
    func staleReasonDoesNotReturn() throws {
        let store = CDAttendanceStore(context: context, role: .leadGuide)
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        let record = try #require(try store.ensureRecord(for: maya, on: try CoreDataTestHelpers.day("2026-10-13")))
        // As a backup restore or an older import writes a row: the fields
        // one by one, a present mark still carrying last week's reason.
        record.statusRaw = AttendanceStatus.present.rawValue
        record.absenceReasonRaw = AbsenceReason.vacation.rawValue

        #expect(store.updateStatus(record, to: .absent))
        #expect(record.absenceReasonRaw == AbsenceReason.none.rawValue)
        // A reason given with the absence is kept.
        #expect(store.updateAbsenceReason(record, to: .sick))
        #expect(record.absenceReason == .sick)
    }

    // MARK: - #6

    @Test("Insights count the children active anywhere in the timeframe and the one before, without test students")
    func insightsStudentsFollowTheTimeframe() throws {
        let reference = try CoreDataTestHelpers.day("2026-10-14")
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        let leah = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Leah", lastName: "Hart", enrollmentStatus: .withdrawn,
            dateWithdrawn: AppCalendar.addingDays(-5, to: reference)
        )
        // Left in the 30 days before this timeframe: the comparison counts her.
        let noa = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Noa", lastName: "Winter", enrollmentStatus: .withdrawn,
            dateWithdrawn: AppCalendar.addingDays(-40, to: reference)
        )
        let gone = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Rina", lastName: "Peretz", enrollmentStatus: .withdrawn,
            dateWithdrawn: AppCalendar.addingDays(-200, to: reference)
        )
        let danny = CoreDataTestHelpers.seedStudent(in: context, firstName: "Danny", lastName: "De Berry")
        let roster = [maya, leah, noa, gone, danny]
        let range = AttendanceInsightsTimeframe.last30.range(endingAt: reference)
        let prior = AttendanceInsightsTimeframe.last30.priorRange(for: range)

        let counted = AttendanceInsightsService.insightStudents(
            from: roster, range: range, priorRange: prior, show: false, namesRaw: TestStudentsFilter.defaultNames
        )
        #expect(Set(counted.map(\.objectID)) == Set([maya, leah, noa].map(\.objectID)))
        let shown = AttendanceInsightsService.insightStudents(
            from: roster, range: range, priorRange: prior, show: true, namesRaw: TestStudentsFilter.defaultNames
        )
        #expect(Set(shown.map(\.objectID)) == Set([maya, leah, noa, danny].map(\.objectID)))

        // Leah's absences before she left count toward the rate.
        for offset in [-8, -7] {
            let record = CDAttendanceRecord(context: context)
            record.studentID = leah.cloudKitKey
            record.date = AppCalendar.addingDays(offset, to: reference)
            record.status = .absent
        }
        #expect(context.safeSave())
        let insights = AttendanceInsightsService.sidebarInsights(
            range: range, priorRange: prior, students: counted, context: context
        )
        #expect(insights.summary.absentCount == 2)
    }

    // MARK: - #7

    #if os(iOS)
    @Test("Left Early is a child going home: no arrival bell, sparkles or wave")
    func leftEarlyIsNotAnArrival() {
        #expect(TileTapMotion.Kind(.leftEarly) != .here)
        #expect(TileTapMotion.Kind(.leftEarly) == .cleared)
        #expect(TileTapMotion.Kind(.present) == .here)
        #expect(TileTapMotion.Kind(.tardy) == .here)
    }
    #endif

    @Test("A Feb 29 birthday falls on Feb 28 in a common year on the roster, as on the tile")
    func leapDayBirthdayOnTheTwentyEighth() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        func day(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
            try #require(calendar.date(from: DateComponents(year: year, month: month, day: day)))
        }
        let born = try day(2016, 2, 29)
        func next(after today: Date) -> Date {
            RosterBirthday.nextOccurrence(of: born, using: calendar, today: today)
        }
        #expect(try next(after: day(2026, 9, 22)) == day(2027, 2, 28))
        #expect(try next(after: day(2027, 2, 28)) == day(2027, 2, 28))
        #expect(try next(after: day(2027, 3, 1)) == day(2028, 2, 29))
        #expect(try AttendanceBirthday.on(day(2027, 2, 28), birthday: born, calendar: calendar) == .birthday)
    }
}
