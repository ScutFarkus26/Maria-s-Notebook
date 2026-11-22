import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Who's in class (domain logic review 2026-11-20, R7): one rule,
/// `CDStudent.isInClass(on:)`, read by every screen. A child with a last
/// day is in class through it; a departed child with no last day is out.
@Suite("Who's in class")
@MainActor
struct StudentInClassTests {
    private let calendar = AppCalendar.shared

    /// Monday 16 to Saturday 21 November 2026; Maya's last day is Friday 20.
    private func day(_ dayOfMonth: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: dayOfMonth, hour: hour))!
    }

    private var schoolWeek: [Date] { (16...20).map { day($0) } }
    private var saturday: Date { day(21) }

    private struct Room {
        let context: NSManagedObjectContext
        let maya: CDStudent
        let ora: CDStudent
    }

    /// Maya withdrew with Friday as her last day (typed in the afternoon, so
    /// the day, not the time, has to decide). Ora stays.
    private func makeRoom() throws -> Room {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Maya", lastName: "Stern",
            enrollmentStatus: .withdrawn, dateWithdrawn: day(20, hour: 15)
        )
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        #expect(CoreDataTestHelpers.save(context))
        return Room(context: context, maya: maya, ora: ora)
    }

    private func fetchNames(_ predicate: NSPredicate, in context: NSManagedObjectContext) -> Set<String> {
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = predicate
        return Set(context.safeFetch(request).map(\.firstName))
    }

    @Test("Maya leaving Friday stays on every screen through Friday, and is gone on Saturday")
    func mayaStaysThroughFriday() throws {
        let room = try makeRoom()
        let both: Set<String> = ["Maya", "Ora"]
        for weekday in schoolWeek {
            #expect(room.maya.isInClass(on: weekday))
            #expect(!room.maya.hasLeft(by: weekday))
            // The attendance roll, in memory and as a fetch.
            #expect(AttendanceRoster.wasEnrolled(room.maya, on: weekday, calendar: calendar))
            let roll = AttendanceRoster.predicate(on: weekday, recordStudentIDs: [], calendar: calendar)
            #expect(fetchNames(roll, in: room.context) == both)
            // Today's lists, the roster and the pickers.
            #expect(fetchNames(CDStudent.notLeftPredicate(by: weekday), in: room.context) == both)
            #expect(Set([room.maya, room.ora].filterEnrolled(now: weekday).map(\.firstName)) == both)
        }

        #expect(!room.maya.isInClass(on: saturday))
        #expect(room.maya.hasLeft(by: saturday))
        #expect(!AttendanceRoster.wasEnrolled(room.maya, on: saturday, calendar: calendar))
        let saturdayRoll = AttendanceRoster.predicate(on: saturday, recordStudentIDs: [], calendar: calendar)
        #expect(fetchNames(saturdayRoll, in: room.context) == ["Ora"])
        #expect(fetchNames(CDStudent.notLeftPredicate(by: saturday), in: room.context) == ["Ora"])
        #expect([room.maya, room.ora].filterEnrolled(now: saturday).map(\.firstName) == ["Ora"])
    }

    @Test("This year's history and the classroom share keep her; later ones don't")
    func periodsSheWasIn() throws {
        let room = try makeRoom()
        let thisWeek = DateRange(start: day(16, hour: 0), end: day(23, hour: 0))
        let nextWeek = DateRange(start: day(23, hour: 0), end: day(30, hour: 0))
        #expect(room.maya.isActive(in: thisWeek))
        #expect(!room.maya.isActive(in: nextWeek))

        let lastDay = day(20, hour: 15)
        let fromMonday = ClassroomShareScope(cutoff: day(16))
        let fromSaturday = ClassroomShareScope(cutoff: saturday)
        #expect(fromMonday.studentBelongs(status: .withdrawn, dateWithdrawn: lastDay, hasAttendanceThisYear: false))
        #expect(!fromSaturday.studentBelongs(status: .withdrawn, dateWithdrawn: lastDay, hasAttendanceThisYear: false))
    }

    @Test("A departed child with no last day is out; an enrolled one is in")
    func departedWithNoDateIsOut() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let gone = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Talia", lastName: "Rosen", enrollmentStatus: .transferred
        )
        let here = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        #expect(CoreDataTestHelpers.save(context))

        #expect(!gone.isInClass(on: day(16)))
        #expect(!gone.isActive(in: DateRange(start: day(1, hour: 0), end: day(30, hour: 0))))
        #expect(!AttendanceRoster.wasEnrolled(gone, on: day(16), calendar: calendar))
        #expect(here.isInClass(on: day(16)))
        #expect(fetchNames(CDStudent.notLeftPredicate(by: day(16)), in: context) == ["Ora"])
    }

    @Test("A child who starts after the day isn't on that day's roll")
    func notStartedYet() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let starter = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Noa", lastName: "Katz", dateStarted: day(18)
        )
        #expect(CoreDataTestHelpers.save(context))
        #expect(!starter.isInClass(on: day(17)))
        #expect(starter.isInClass(on: day(18)))
    }
}
