import Foundation
import CoreData

// The planner's inputs, read from the store: the children and each child's
// mark for a day, from the record that wins among the day's duplicates.

nonisolated extension ParentLockerPlanner.Child {
    /// The notebook child as matching needs them; nil for a record with no id.
    init?(_ student: CDStudent) {
        guard let id = student.id else { return nil }
        self.init(
            id: id,
            firstName: student.firstName,
            lastName: student.lastName,
            nickname: student.nickname,
            parentLockerID: student.parentLockerID
        )
    }
}

nonisolated extension ParentLockerPlanner.DayMark {
    init(_ record: CDAttendanceRecord) {
        self.init(
            statusRaw: record.statusRaw,
            absenceReasonRaw: record.absenceReasonRaw,
            leftAt: record.leftAt,
            statusBeforeLeavingRaw: record.statusBeforeLeavingRaw
        )
    }
}

nonisolated extension ParentLockerPlanner {

    /// Each child's mark on `day`, by student id, from the record the grid
    /// and reports read when CloudKit has left more than one
    /// (`deduplicatedPerStudentDay`). `studentIDs` limits it to those
    /// children; nil reads the whole day.
    static func dayMarks(
        on day: Date, for studentIDs: Set<UUID>? = nil, in context: NSManagedObjectContext
    ) -> [UUID: DayMark] {
        let request = CDFetchRequest(CDAttendanceRecord.self)
        request.predicate = NSPredicate(format: "date == %@", AppCalendar.startOfDay(day) as NSDate)
        scopeToClassroom(request, in: context)
        var result: [UUID: DayMark] = [:]
        for record in context.safeFetch(request).deduplicatedPerStudentDay() {
            guard let id = UUID(uuidString: record.studentID),
                  studentIDs?.contains(id) ?? true else { continue }
            result[id] = DayMark(record)
        }
        return result
    }

    /// In the Assistant, reads only the classroom share, as the roll does
    /// (`AssistantDayRoll`): on an Apple Account that also keeps a notebook of
    /// its own, the private store holds that notebook's marks.
    private static func scopeToClassroom<T>(_ request: NSFetchRequest<T>, in context: NSManagedObjectContext) {
        #if ASSISTANT_APP
        let shared = context.persistentStoreCoordinator?.persistentStores.first {
            $0.configurationName == CoreDataStack.sharedConfiguration
        }
        if let shared { request.affectedStores = [shared] }
        #endif
    }
}
