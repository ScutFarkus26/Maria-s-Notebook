import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

/// One class on an in-memory stack, a grid on a 2031 Monday with a clock the
/// test moves by hand, and the guide's device writing to the same store as
/// if synced in. Each grid gets its own defaults suite unless given one.
@MainActor
struct AssistantGridFixture {

    typealias Model = AssistantAttendanceViewModel

    /// A clock the tests move by hand.
    final class Clock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    let stack: CoreDataStack
    let monday: Date
    var context: NSManagedObjectContext { stack.viewContext }

    init() throws {
        stack = try AssistantTestSupport.makeStack()
        monday = try AssistantTestSupport.day("2031-01-06")
    }

    /// The children, saved.
    @discardableResult
    func classOf(_ firsts: [String]) -> [CDStudent] {
        let students = firsts.map { AssistantTestSupport.student($0, "Cedar", in: context) }
        _ = context.safeSave()
        return students
    }

    /// The grid on `day` (Monday when nil), told the time by `clock` (9 AM
    /// that day when nil), loaded.
    func model(
        on day: Date? = nil, clock: Clock? = nil, defaults: UserDefaults = AssistantTestSupport.makeDefaults()
    ) -> Model {
        let day = day ?? monday
        let clock = clock ?? Clock(day.addingTimeInterval(9 * 3_600))
        let model = Model(context: context, container: nil, date: day, defaults: defaults, now: { clock.now })
        model.load()
        return model
    }

    func row(_ first: String, in model: Model) throws -> Model.Row {
        try #require(model.rows.first { $0.student.firstName == first })
    }

    /// The guide's device.
    var guide: CDAttendanceStore { CDAttendanceStore(context: context, role: .leadGuide) }

    /// The record the day shows for `student`.
    func record(of student: CDStudent, on day: Date) throws -> CDAttendanceRecord {
        try #require(try guide.loadRecords(for: day).deduplicatedPerStudentDay().first {
            $0.studentID == student.id?.uuidString
        })
    }
}
