import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// A small classroom for the Groups builders: two sub-areas in an in-memory
/// store, children seeded per test, and a fixed "today" so waits are exact.
///
/// - Math › Laws: Commutative (1), Distributive (2), Associative (3), Identity (4)
/// - Geometry › Shapes: Triangle (1), Square (2), Pentagon (3)
@MainActor
struct ReadyGroupsFixture {
    let context: NSManagedObjectContext
    let commutative: CDLesson
    let distributive: CDLesson
    let associative: CDLesson
    let identity: CDLesson
    let triangle: CDLesson
    let square: CDLesson
    let pentagon: CDLesson

    var laws: [CDLesson] { [commutative, distributive, associative, identity] }
    var shapes: [CDLesson] { [triangle, square, pentagon] }
    var lessons: [CDLesson] { laws + shapes }

    /// "Today" for every wait: 2026-04-30.
    static let today = "2026-04-30"

    init() throws {
        let context = try CoreDataTestHelpers.makeContext()
        func lesson(_ name: String, _ area: String, _ sequence: String, _ order: Int64) -> CDLesson {
            let lesson = CoreDataTestHelpers.seedLesson(in: context, name: name, area: area, sequence: sequence)
            lesson.orderInSequence = order
            return lesson
        }
        self.context = context
        commutative = lesson("Commutative Law", "Math", "Laws", 10)
        distributive = lesson("Distributive Law", "Math", "Laws", 20)
        associative = lesson("Associative Law", "Math", "Laws", 30)
        identity = lesson("Identity", "Math", "Laws", 40)
        triangle = lesson("Triangle", "Geometry", "Shapes", 10)
        square = lesson("Square", "Geometry", "Shapes", 20)
        pentagon = lesson("Pentagon", "Geometry", "Shapes", 30)
    }

    // MARK: - Seeding

    func student(_ first: String, _ last: String, level: CDStudent.Level = .lower) -> CDStudent {
        CoreDataTestHelpers.seedStudent(in: context, firstName: first, lastName: last, level: level)
    }

    /// Gives `lesson` to `students` on `day`, confirming each when asked.
    @discardableResult
    func give(
        _ students: [CDStudent], _ lesson: CDLesson, on day: String, confirmed: Bool = false
    ) throws -> CDLessonAssignment {
        let given = PresentationFactory.makePresented(
            lesson: lesson, students: students, presentedAt: try CoreDataTestHelpers.day(day), context: context
        )
        if confirmed {
            for student in students {
                given.confirmStudent(try #require(student.id))
            }
        }
        return given
    }

    /// An unpresented assignment of `lesson` for `students`, dated when `day` is given.
    @discardableResult
    func plan(_ students: [CDStudent], _ lesson: CDLesson, on day: String?) throws -> CDLessonAssignment {
        guard let day else {
            return PresentationFactory.makeDraft(lesson: lesson, students: students, context: context)
        }
        return PresentationFactory.makeScheduled(
            lesson: lesson, students: students, scheduledFor: try CoreDataTestHelpers.day(day), context: context
        )
    }

    /// A live year-plan entry for one child.
    func yearPlan(_ student: CDStudent, _ lesson: CDLesson, on day: String) throws {
        let entry = CDYearPlanEntry(context: context)
        entry.studentID = try #require(student.id).uuidString
        entry.lessonID = try #require(lesson.id).uuidString
        entry.plannedDate = try CoreDataTestHelpers.day(day)
        entry.statusRaw = YearPlanEntryStatus.planned.rawValue
    }

    /// A sub-area that holds a child at "almost" while her practice is open.
    func requirePractice(area: String, sequence: String) {
        let settings = CDLessonSequenceSettings(context: context)
        settings.area = area
        settings.sequence = sequence
        settings.requiresPractice = true
        settings.requiresTeacherConfirmation = false
    }

    func work(_ student: CDStudent, on lesson: CDLesson, status: String) throws {
        let work = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "\(lesson.name) practice",
            studentID: try #require(student.id), lessonID: try #require(lesson.id)
        )
        work.statusRaw = status
    }

    // MARK: - Building

    /// Saves, reads the record over `students`, and runs the ready queue,
    /// the way the Groups page will.
    func snapshot(_ students: [CDStudent]) throws -> ReadyQueueSnapshot {
        #expect(CoreDataTestHelpers.save(context))
        let ids = try students.map { try #require($0.id).uuidString }
        let index = PresentationRecordIndex(students: Set(ids), in: context)
        return ReadyQueueSnapshot(students: students, lessons: lessons, index: index, in: context)
    }

    /// Calendar days from `date` to `today`: a stand-in for the school-day
    /// counter that needs no school calendar.
    static func daysSince(_ date: Date) -> Int {
        guard let today = MCPNotebookTools.isoDay.date(from: Self.today).map(AppCalendar.startOfDay) else {
            return -1
        }
        return AppCalendar.shared.dateComponents([.day], from: AppCalendar.startOfDay(date), to: today).day ?? -1
    }

    // MARK: - IDs

    func id(_ lesson: CDLesson) throws -> String {
        try #require(lesson.id).uuidString
    }

    func id(_ student: CDStudent) throws -> String {
        try #require(student.id).uuidString
    }
}
