import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Seeds for `PresentationRecordIndexRowPathTests`: the record rows that are
/// easy to fold wrong, the April-backup-sized record, and a small classroom
/// for Today's ready queue and the MCP sweeps.
@MainActor
enum RecordIndexRowPathFixture {

    /// How an assignment in the fixture stands.
    enum Stage {
        case given(Date)
        case undated
        case draft
        case scheduled(Date)
    }

    /// The record keys children and lessons by id string, so the fixture uses
    /// plain strings and can name a child the roster has never heard of.
    struct OddRecord {
        let ada: String, ben: String, cy: String, dee: String, eve: String
        let first: String, second: String, third: String, fourth: String
        let march11: Date, march12: Date, april2: Date

        var students: [String] { [ada, ben, cy, dee, eve] }
        var lessons: [String] { [first, second, third, fourth] }
        /// Every id a question is put about, including ones nothing names.
        var askedStudents: [String] { students + ["", "outsider", "nobody"] }
        var askedLessons: [String] { lessons + ["", "no-such-lesson"] }
    }

    /// Rows that are easy to fold wrong, a few of each:
    /// - presentation rows: one day twice (once with a time), a second day,
    ///   undated but mastered, proficient with no mastery date, an unknown
    ///   state, an exact duplicate, an empty student id, an empty lesson id;
    /// - assignments: a pair with one confirmed, a later pass, two given at
    ///   the same instant and two undated marks for one child (ties for the
    ///   latest), a draft, a scheduled one, empty / nil / malformed rosters,
    ///   an unknown state, a child off the roster, a malformed confirmation
    ///   list, a confirmation on a draft;
    /// - year-plan entries: planned, promoted, skipped, an unknown status, a
    ///   duplicate, and a skipped twin of a planned entry.
    ///
    /// On the split SQLite store three presentation rows (Cy's pair and the
    /// empty student id) go to the shared store, where an assistant's
    /// classroom rows live, so every read spans both stores.
    static func seedOddRecord(in context: NSManagedObjectContext) throws -> OddRecord {
        let record = OddRecord(
            ada: UUID().uuidString, ben: UUID().uuidString, cy: UUID().uuidString,
            dee: UUID().uuidString, eve: UUID().uuidString,
            first: UUID().uuidString, second: UUID().uuidString,
            third: UUID().uuidString, fourth: UUID().uuidString,
            march11: try CoreDataTestHelpers.day("2026-03-11"),
            march12: try CoreDataTestHelpers.day("2026-03-12"),
            april2: try CoreDataTestHelpers.day("2026-04-02")
        )
        seedOddPresentationRows(record, in: context)
        seedOddAssignments(record, in: context)
        seedOddPlanEntries(record, in: context)
        #expect(CoreDataTestHelpers.save(context))
        return record
    }

    private static func seedOddPresentationRows(_ record: OddRecord, in context: NSManagedObjectContext) {
        @discardableResult
        func row(
            _ student: String, _ lesson: String, on day: Date?, masteredAt: Date? = nil, state: String? = nil
        ) -> CDLessonPresentation {
            let row = CDLessonPresentation(context: context)
            row.studentID = student
            row.lessonID = lesson
            row.presentedAt = day
            row.masteredAt = masteredAt
            if let state { row.stateRaw = state }
            return row
        }
        row(record.ada, record.first, on: record.march11)
        row(record.ada, record.first, on: record.march11.addingTimeInterval(3 * 3_600))
        row(record.ada, record.first, on: record.march12)
        row(record.ada, record.second, on: nil, masteredAt: record.april2)
        row(record.ben, record.second, on: record.march11, state: LessonPresentationState.proficient.rawValue)
        row(record.ben, record.third, on: record.march12, state: "bogus")
        let sharedRows = [
            row(record.cy, record.first, on: record.march11),
            row(record.cy, record.first, on: record.march11),
            row("", record.fourth, on: record.march11)
        ]
        row(record.dee, "", on: record.march12)
        row(record.eve, record.fourth, on: nil)

        let sharedStore = context.persistentStoreCoordinator?.persistentStores
            .first { $0.configurationName == CoreDataStack.sharedConfiguration }
        if let sharedStore {
            for row in sharedRows { context.assign(row, to: sharedStore) }
        }
    }

    private static func seedOddAssignments(_ record: OddRecord, in context: NSManagedObjectContext) {
        @discardableResult
        func assignment(
            _ lesson: String, _ students: [String], _ stage: Stage, confirmed: [String] = []
        ) -> CDLessonAssignment {
            let assignment = CDLessonAssignment(context: context)
            assignment.lessonID = lesson
            assignment.studentIDs = students
            switch stage {
            case .given(let day): assignment.markPresented(at: day, snapshotLesson: false)
            case .undated: assignment.markPreviouslyPresented(snapshotLesson: false)
            case .draft: break
            case .scheduled(let day): assignment.schedule(for: day)
            }
            if !confirmed.isEmpty { assignment.confirmedStudentIDs = confirmed }
            return assignment
        }
        let (ada, ben, cy, dee, eve) = (record.ada, record.ben, record.cy, record.dee, record.eve)
        assignment(record.first, [ada, ben], .given(record.march11), confirmed: [ben])
        assignment(record.first, [ada], .given(record.march12), confirmed: [ada])
        assignment(record.second, [cy], .given(record.march12))
        assignment(record.second, [cy], .given(record.march12))
        assignment(record.third, [dee], .undated)
        assignment(record.third, [dee], .undated)
        assignment(record.fourth, [ada, eve], .draft)
        assignment(record.third, [ben], .scheduled(record.april2))
        assignment(record.first, [], .given(record.march11))
        assignment(record.first, [ada], .given(record.march11))._studentIDsData = nil
        assignment(record.second, [ada], .given(record.march11))._studentIDsData = Data("not json".utf8)
        assignment(record.second, [eve], .given(record.march11)).stateRaw = "bogus"
        assignment(record.fourth, [ada, "outsider"], .given(record.april2))
        assignment(record.third, [eve], .given(record.april2))._confirmedStudentIDsData = Data("{".utf8)
        assignment(record.first, [cy], .given(record.april2), confirmed: [cy, "outsider"])
        assignment(record.second, [ben], .draft, confirmed: [ben])
    }

    private static func seedOddPlanEntries(_ record: OddRecord, in context: NSManagedObjectContext) {
        func entry(_ student: String, _ lesson: String, _ status: String) {
            let entry = CDYearPlanEntry(context: context)
            entry.studentID = student
            entry.lessonID = lesson
            entry.statusRaw = status
        }
        entry(record.ada, record.third, YearPlanEntryStatus.planned.rawValue)
        entry(record.ada, record.third, YearPlanEntryStatus.skipped.rawValue)
        entry(record.ben, record.fourth, YearPlanEntryStatus.promoted.rawValue)
        entry(record.cy, record.fourth, YearPlanEntryStatus.skipped.rawValue)
        entry(record.dee, record.first, "bogus")
        entry(record.eve, record.second, YearPlanEntryStatus.planned.rawValue)
        entry(record.eve, record.second, YearPlanEntryStatus.planned.rawValue)
    }

    /// A record the size of April's backup (1,782 presentation rows, 481
    /// assignments) plus 300 year-plan entries, over 30 children and 60
    /// lessons.
    static func seedAprilScale(in context: NSManagedObjectContext) throws -> (students: [String], lessons: [String]) {
        let students = (0..<30).map { _ in UUID().uuidString }
        let lessons = (0..<60).map { _ in UUID().uuidString }
        let start = try CoreDataTestHelpers.day("2025-09-01")
        func day(_ offset: Int) -> Date { start.addingTimeInterval(Double(offset % 200) * 86_400) }

        for index in 0..<1_782 {
            let row = CDLessonPresentation(context: context)
            row.studentID = students[index % 30]
            row.lessonID = lessons[(index / 30) % 60]
            row.presentedAt = index % 11 == 0 ? nil : day(index)
            if index % 7 == 0 { row.masteredAt = day(index + 14) }
        }
        for index in 0..<481 {
            let assignment = CDLessonAssignment(context: context)
            assignment.lessonID = lessons[index % 60]
            assignment.studentIDs = (0..<3).map { students[(index + $0) % 30] }
            if index % 5 != 0 { assignment.markPresented(at: day(index), snapshotLesson: false) }
            if index % 3 == 0 { assignment.confirmedStudentIDs = [students[index % 30]] }
        }
        for index in 0..<300 {
            let entry = CDYearPlanEntry(context: context)
            entry.studentID = students[index % 30]
            entry.lessonID = lessons[(index * 7) % 60]
            if index % 4 == 0 { entry.status = .skipped }
        }
        #expect(CoreDataTestHelpers.save(context))
        return (students, lessons)
    }

    /// Math › Laws, Commutative then Distributive. Avital and Noa were given
    /// Commutative together and Avital was confirmed on it; Noa also has a
    /// record row for it and a plan for Distributive.
    static func seedReadyClassroom(in context: NSManagedObjectContext) throws {
        let commutative = CoreDataTestHelpers.seedLesson(
            in: context, name: "Commutative Law", area: "Math", sequence: "Laws"
        )
        commutative.orderInSequence = 10
        let distributive = CoreDataTestHelpers.seedLesson(
            in: context, name: "Distributive Law", area: "Math", sequence: "Laws"
        )
        distributive.orderInSequence = 20
        let avital = CoreDataTestHelpers.seedStudent(in: context, firstName: "Avital", lastName: "Beyderman")
        let noa = CoreDataTestHelpers.seedStudent(in: context, firstName: "Noa", lastName: "Cohen")
        let given = PresentationFactory.makePresented(
            lesson: commutative, students: [avital, noa],
            presentedAt: try CoreDataTestHelpers.day("2026-03-11"), context: context
        )
        given.confirmStudent(try #require(avital.id))
        let row = CDLessonPresentation(context: context)
        row.studentID = try #require(noa.id).uuidString
        row.lessonID = try #require(commutative.id).uuidString
        let plan = CDYearPlanEntry(context: context)
        plan.studentID = try #require(noa.id).uuidString
        plan.lessonID = try #require(distributive.id).uuidString
        #expect(CoreDataTestHelpers.save(context))
    }
}
