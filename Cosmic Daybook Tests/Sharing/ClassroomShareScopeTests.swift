import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// `ClassroomShareScope`: the share holds this school year only — enrolled children, the
/// ones who left this year, and attendance from the first day on.
@Suite("Classroom share scope")
@MainActor
struct ClassroomShareScopeTests {

    /// Aug 25 of some year, as the school-year start.
    private let cutoff: Date = {
        let date = AppCalendar.shared.date(from: DateComponents(year: 2026, month: 8, day: 25))!
        return AppCalendar.startOfDay(date)
    }()

    private func day(_ offset: Int) -> Date {
        AppCalendar.shared.date(byAdding: .day, value: offset, to: cutoff)!
    }

    private var scope: ClassroomShareScope { ClassroomShareScope(cutoff: cutoff) }

    // MARK: - Students

    @Test("Enrolled children always belong, whatever their dates")
    func enrolledBelongs() {
        #expect(scope.studentBelongs(status: .enrolled, dateWithdrawn: nil, hasAttendanceThisYear: false))
        #expect(scope.studentBelongs(status: .enrolled, dateWithdrawn: day(-400), hasAttendanceThisYear: false))
    }

    @Test("A child who left last year is out; one who left on or after the first day stays")
    func departureDate() {
        #expect(!scope.studentBelongs(status: .withdrawn, dateWithdrawn: day(-1), hasAttendanceThisYear: false))
        #expect(scope.studentBelongs(status: .withdrawn, dateWithdrawn: day(0), hasAttendanceThisYear: false))
        #expect(scope.studentBelongs(status: .transferred, dateWithdrawn: day(40), hasAttendanceThisYear: false))
        // Late in the day on the first day still counts as that day.
        let lateFirstDay = day(0).addingTimeInterval(20 * 3_600)
        #expect(scope.studentBelongs(status: .withdrawn, dateWithdrawn: lateFirstDay, hasAttendanceThisYear: false))
    }

    @Test("A departed child with no date stays when she has attendance this year, else goes")
    func noDate() {
        #expect(!scope.studentBelongs(status: .withdrawn, dateWithdrawn: nil, hasAttendanceThisYear: false))
        #expect(scope.studentBelongs(status: .withdrawn, dateWithdrawn: nil, hasAttendanceThisYear: true))
        // A placeholder date from last year doesn't beat this year's marks.
        #expect(scope.studentBelongs(status: .transferred, dateWithdrawn: day(-300), hasAttendanceThisYear: true))
    }

    // MARK: - Attendance

    @Test("Attendance from the first day on, for a child who belongs, and ids match in any case")
    func attendance() {
        let ada = UUID().uuidString
        let belonging: Set<String> = [ClassroomShareScope.normalizedID(ada)]
        #expect(scope.attendanceBelongs(date: day(0), studentID: ada, belongingStudentIDs: belonging))
        #expect(scope.attendanceBelongs(date: day(0), studentID: ada.lowercased(), belongingStudentIDs: belonging))
        #expect(!scope.attendanceBelongs(
            date: day(0).addingTimeInterval(-1), studentID: ada, belongingStudentIDs: belonging
        ))
        #expect(!scope.attendanceBelongs(date: nil, studentID: ada, belongingStudentIDs: belonging))
        #expect(!scope.attendanceBelongs(date: day(5), studentID: UUID().uuidString, belongingStudentIDs: belonging))
    }

    // MARK: - Reading the store

    @Test("Reading the store: who belongs, and which records the fetch predicates select")
    func storeReads() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let current = student(in: ctx, status: .enrolled, withdrawn: nil)
        let leftMidYear = student(in: ctx, status: .withdrawn, withdrawn: day(20))
        let leftLastYear = student(in: ctx, status: .transferred, withdrawn: day(-60))
        let noDateButMarked = student(in: ctx, status: .withdrawn, withdrawn: nil)
        let noDateNoMarks = student(in: ctx, status: .withdrawn, withdrawn: nil)

        let marks = [
            mark(current, on: day(6), in: ctx, lowercased: true),
            mark(current, on: day(-120), in: ctx),
            mark(leftMidYear, on: day(6), in: ctx),
            mark(leftLastYear, on: day(-120), in: ctx),
            mark(noDateButMarked, on: day(8), in: ctx),
            mark(noDateNoMarks, on: day(-3), in: ctx)
        ]
        #expect(CoreDataTestHelpers.save(ctx))

        let belonging = scope.belongingStudentIDs(in: ctx, store: nil)
        let expected = [current, leftMidYear, noDateButMarked].compactMap { $0.id?.uuidString }
        #expect(belonging == Set(expected))

        for (entity, want) in [
            ("Student", Set([current, leftMidYear, noDateButMarked].map(\.objectID))),
            ("AttendanceRecord", Set([marks[0], marks[2], marks[4]].map(\.objectID)))
        ] {
            let request = NSFetchRequest<NSManagedObjectID>(entityName: entity)
            request.resultType = .managedObjectIDResultType
            request.predicate = scope.predicate(for: entity, belongingStudentIDs: belonging)
            #expect(Set(try ctx.fetch(request)) == want, "\(entity)")
        }
        #expect(scope.predicate(for: "NonSchoolDay", belongingStudentIDs: belonging) == nil)
    }

    @Test("Attendance in the two weeks before the start means the start is set too late")
    func startSetTooLate() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let child = student(in: ctx, status: .enrolled, withdrawn: nil)
        mark(child, on: day(-60), in: ctx) // last spring: fine
        #expect(CoreDataTestHelpers.save(ctx))
        #expect(scope.attendanceJustBeforeCutoff(in: ctx, store: nil) == nil)

        mark(child, on: day(-1), in: ctx) // the real first day, before the setting's
        #expect(CoreDataTestHelpers.save(ctx))
        #expect(scope.attendanceJustBeforeCutoff(in: ctx, store: nil) == day(-1))
    }

    @Test(
        "The attendance predicate matches a student id in any case and with spaces around it, in SQLite too",
        arguments: [false, true]
    )
    func predicateMatchesAnySpelling(sqlite: Bool) throws {
        let ctx = sqlite
            ? try CoreDataTestHelpers.makeSplitStoreContext()
            : try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let child = student(in: ctx, status: .enrolled, withdrawn: nil)
        let id = try #require(child.id?.uuidString)
        let mixed = id.prefix(8).lowercased() + id.dropFirst(8)
        var matching: [CDAttendanceRecord] = []
        for spelling in [id, id.lowercased(), mixed, " \(id) ", "\(id.lowercased())\n"] {
            let record = mark(child, on: day(5), in: ctx)
            record.studentID = spelling
            matching.append(record)
        }
        let other = mark(child, on: day(5), in: ctx)
        other.studentID = "x\(id)" // not the same id once trimmed
        mark(child, on: day(-5), in: ctx) // before the start
        #expect(CoreDataTestHelpers.save(ctx))

        let belonging = scope.belongingStudentIDs(in: ctx, store: nil)
        let request = NSFetchRequest<NSManagedObjectID>(entityName: "AttendanceRecord")
        request.resultType = .managedObjectIDResultType
        request.predicate = scope.predicate(for: "AttendanceRecord", belongingStudentIDs: belonging)
        #expect(Set(try ctx.fetch(request)) == Set(matching.map(\.objectID)))
        // The release's own rule agrees on every one.
        for record in matching {
            let studentID = record.studentID
            #expect(scope.attendanceBelongs(date: record.date, studentID: studentID, belongingStudentIDs: belonging))
        }

        // No one belongs: nothing matches (not every blank id).
        request.predicate = scope.predicate(for: "AttendanceRecord", belongingStudentIDs: [])
        #expect(try ctx.fetch(request).isEmpty)
    }

    // MARK: - Helpers

    private func student(
        in ctx: NSManagedObjectContext, status: CDStudent.EnrollmentStatus, withdrawn: Date?
    ) -> CDStudent {
        let student = CDStudent(context: ctx)
        student.firstName = "Child"
        student.enrollmentStatus = status
        student.dateWithdrawn = withdrawn
        return student
    }

    @discardableResult
    private func mark(
        _ student: CDStudent, on date: Date, in ctx: NSManagedObjectContext, lowercased: Bool = false
    ) -> CDAttendanceRecord {
        let record = CDAttendanceRecord(context: ctx)
        let id = student.id?.uuidString ?? ""
        record.studentID = lowercased ? id.lowercased() : id
        record.date = date
        record.status = .present
        return record
    }
}
