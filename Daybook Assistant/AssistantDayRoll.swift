import Foundation
import CoreData

/// The children on one day's attendance, in the grid's order.
///
/// The grid, Close Arrival by Siri and "Who's not here yet" all read this one
/// list (`AttendanceRoster`'s day roll), so a voice command never marks a
/// child the grid doesn't show. Siri used to take every enrolled child
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
        return context.safeFetch(request)
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

    /// The fewest letters that still tell each child apart: the first name
    /// alone ("Ari"), the last initial only where a first name is shared
    /// ("Etty G", "Etty R"), and the full name where the initials clash too.
    /// Kept to this app on purpose; everywhere else the notebook's short
    /// form is always "Maya S".
    static func gridNames(for students: [CDStudent]) -> [NSManagedObjectID: String] {
        func key(_ name: String) -> String { name.trimmed().lowercased() }
        let firstNameCounts = Dictionary(grouping: students) { key($0.firstName) }.mapValues(\.count)
        let shortNameCounts = Dictionary(grouping: students) { key($0.shortName) }.mapValues(\.count)
        var names: [NSManagedObjectID: String] = [:]
        for student in students {
            let first = student.firstName.trimmed()
            if !first.isEmpty, firstNameCounts[key(first)] == 1 {
                names[student.objectID] = first
            } else if shortNameCounts[key(student.shortName)] == 1 {
                names[student.objectID] = student.shortName
            } else {
                names[student.objectID] = student.fullName
            }
        }
        return names
    }

    /// Siri's day: today's roll, and the children on it with no mark yet.
    static func today(
        in session: SiriAttendance
    ) throws -> (roll: [CDStudent], unmarked: [CDStudent]) {
        let records = try session.store.loadRecords(for: session.today).deduplicatedPerStudentDay()
        let roll = students(
            on: session.today,
            recordStudentIDs: Set(records.map(\.studentID)),
            in: session.context
        )
        let marked = Set(records.filter { $0.status != .unmarked }.map(\.studentID))
        return (roll, roll.filter { !marked.contains($0.id?.uuidString ?? "") })
    }
}
