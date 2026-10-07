import Foundation
import CoreData

/// The children on one day's attendance, in the grid's order.
///
/// The grid, Close Arrival by Siri, "Who's not here yet" and "Who's absent"
/// all read this one list (`AttendanceRoster`'s day roll), so a voice command
/// never marks a child the grid doesn't show. Siri used to take every enrolled child
/// instead: a child typed in ahead of her start date was marked absent, and
/// that record then put her on the grid.
@MainActor
enum AssistantDayRoll {

    /// `day`'s roll. `recordStudentIDs` are the day's records' student ids:
    /// a record puts a child on the roll whatever her dates say.
    static func students(
        on day: Date,
        recordStudentIDs: Set<String>,
        in context: NSManagedObjectContext
    ) -> [CDStudent] {
        let request = classroomStudents(in: context)
        request.predicate = AttendanceRoster.predicate(on: day, recordStudentIDs: recordStudentIDs)
        request.sortDescriptors = CDStudent.sortByName
        return classroom(context.safeFetch(request))
    }

    /// The children the grid and Siri may name, from a fetch of the share's
    /// students: the guide's test students left out, as her own roll leaves
    /// them out (`TestStudentsFilter`; the list is a setting on her device,
    /// so this iPhone hides its default names), and a child who synced in
    /// twice, as two rows with one id, shown once. The guide's notebook
    /// folds such copies; this app may not delete a student, so until the
    /// fold arrives it shows the first. Marks go by the id, so either row
    /// marks the same child.
    static func classroom(_ students: [CDStudent]) -> [CDStudent] {
        var seen = Set<UUID>()
        return TestStudentsFilter.filterVisible(students).filter { student in
            guard let id = student.id else { return true }
            return seen.insert(id).inserted
        }
    }

    /// A fetch of the classroom share's children only. On an Apple Account
    /// that also keeps a Cosmic Daybook of its own, the private store holds
    /// that notebook's children too, and a mark on one would be filed into
    /// the guide's share. Stacks without a shared store (tests, the sample
    /// class) read everything.
    static func classroomStudents(in context: NSManagedObjectContext) -> NSFetchRequest<CDStudent> {
        let request = CDFetchRequest(CDStudent.self)
        let shared = context.persistentStoreCoordinator?.persistentStores.first {
            $0.configurationName == CoreDataStack.sharedConfiguration
        }
        if let shared { request.affectedStores = [shared] }
        return request
    }

    /// The earliest day the classroom share holds attendance for, or nil when it holds none.
    /// The share keeps this school year only, so the grid doesn't page back past it: earlier
    /// days would show today's children unmarked, and a mark there would be filed outside
    /// the year the guide shares (`ClassroomShareScope`).
    static func earliestRecordDay(in context: NSManagedObjectContext) -> Date? {
        let request = CDFetchRequest(CDAttendanceRecord.self)
        let shared = context.persistentStoreCoordinator?.persistentStores.first {
            $0.configurationName == CoreDataStack.sharedConfiguration
        }
        if let shared { request.affectedStores = [shared] }
        request.predicate = NSPredicate(format: "date != nil")
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        request.fetchLimit = 1
        return context.safeFetchFirst(request)?.date.map { Calendar.current.startOfDay(for: $0) }
    }

    /// Siri's day: today's roll, the children on it with no mark yet, and
    /// those marked absent.
    static func today(
        in session: SiriAttendance
    ) throws -> (roll: [CDStudent], unmarked: [CDStudent], absent: [CDStudent]) {
        let records = try session.store.loadRecords(for: session.today).deduplicatedPerStudentDay()
        let roll = students(
            on: session.today,
            recordStudentIDs: Set(records.map(\.studentID)),
            in: session.context
        )
        let marked = Set(records.filter { $0.status != .unmarked }.map(\.studentID))
        let absent = Set(records.filter { $0.status == .absent }.map(\.studentID))
        return (
            roll,
            roll.filter { !marked.contains($0.id?.uuidString ?? "") },
            roll.filter { absent.contains($0.id?.uuidString ?? "") }
        )
    }
}
