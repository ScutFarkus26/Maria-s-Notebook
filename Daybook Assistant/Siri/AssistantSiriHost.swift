import CoreData

/// The Assistant's half of the Siri layer: the shared files (the student
/// entity, `SiriAttendance`, the attendance intents) reach the app only
/// through `SiriHost`, which Cosmic Daybook defines with the same shape.
@MainActor
enum SiriHost {
    /// Async to match the notebook's, whose stores open off the main thread.
    static func stack() async throws -> CoreDataStack {
        try AssistantStack.shared()
    }

    /// What Siri says when the class can't be opened (the raw error is logged).
    /// "Assistant" is the app's name on the Home Screen.
    nonisolated static let cannotOpenMessage = "I couldn't open your class. Open the Assistant app to fix it."

    /// Until an invitation is accepted there is no class to mark.
    static func checkReady(in context: NSManagedObjectContext) throws {
        if AssistantSampleClass.isRequested { return }
        let request = CDClassroomMembership.ownRowsRequest()
        request.fetchLimit = 1
        guard context.safeFetchFirst(request) != nil else {
            throw SiriAttendanceError.notReady("Open the Assistant app and join your class first.")
        }
    }

    /// Every enrolled child, and one leaving who is still on today's roll,
    /// for matching a spoken name (`StudentEntityQuery`, `SiriAttendance.nameable`).
    /// Marking goes by the day's roll (`SiriAttendance.student(for:)`), and
    /// commands that act on the whole class use it too (`AssistantDayRoll`).
    static func roster(in context: NSManagedObjectContext) -> [CDStudent] {
        let request = AssistantDayRoll.classroomStudents(in: context)
        request.sortDescriptors = CDStudent.sortByName
        return SiriAttendance.nameable(AssistantDayRoll.classroom(context.safeFetch(request)), in: context)
    }

    /// Nobody: nothing the Assistant does is about a child who has left, and
    /// on a locked phone the answer would tell anyone nearby that she has.
    static func formerStudents(in context: NSManagedObjectContext) -> [CDStudent] { [] }

    /// Siri names children as the grid does: first names, with an initial
    /// only where two share one. Here and late answer on a locked phone,
    /// where a full name tells anyone nearby more than was said.
    static func displayNames(for students: [CDStudent]) -> [NSManagedObjectID: String] {
        AttendanceGridNames.names(for: students)
    }

    /// Hardcoded, as in the grid: this app is only ever used by an assistant.
    static let role: CDClassroomMembership.ClassroomRole? = .assistant

    /// Once arrival has closed, on this phone or another device (Close
    /// Arrival's automatic absence on a record that day), a child who
    /// arrives is late (tardy), exactly as a tap during Late marks them.
    static func statusForHere(on day: Date, store: CDAttendanceStore) -> AttendanceStatus {
        AttendanceLatePhase.isLate(on: day, closedAnywhere: (try? store.arrivalClosed(on: day)) == true)
            ? .tardy : .present
    }

    /// Siri's Undo of a Close Arrival: this phone no longer counts the day
    /// as closed here, and goes by the records again, as the grid's Undo
    /// does. It used to reopen on purpose, so a Close Arrival the guide made
    /// afterwards was ignored here.
    static func closeArrivalUndone(on day: Date) {
        AttendanceLatePhase.setLate(false, on: day)
    }

    /// Whether `day` is a school day by the guide's calendar: the classroom
    /// share's days off and school Saturdays alone, under the school-day rule
    /// (`SchoolDayChecker`). The private store can hold a notebook of her
    /// own on the same Apple Account (as `AssistantDayRoll.classroomStudents`
    /// reads), and its days off made Siri ask about a day of school. A stack
    /// with one store (tests, the Sample Class) reads it all.
    static func isSchoolDay(_ day: Date, in context: NSManagedObjectContext) -> Bool {
        let shared = context.persistentStoreCoordinator?.persistentStores
            .first { $0.configurationName == CoreDataStack.sharedConfiguration }
        let start = AppCalendar.startOfDay(day)
        func days<T: NSManagedObject>(_ type: T.Type) -> Set<Date> {
            let request = CDFetchRequest(type)
            request.predicate = NSPredicate(
                format: "date >= %@ AND date < %@", start as NSDate, AppCalendar.addingDays(1, to: start) as NSDate
            )
            request.affectedStores = shared.map { [$0] }
            let dates = context.safeFetch(request).compactMap { $0.value(forKey: "date") as? Date }
            return Set(dates.map(AppCalendar.startOfDay))
        }
        return !SchoolDayChecker.isNonSchoolDay(
            start, nonSchoolDayDates: days(CDNonSchoolDay.self), overrideDates: days(CDSchoolDayOverride.self)
        )
    }

    /// New marks go into the classroom share explicitly, as the grid's do.
    static func didSave(created: [NSManagedObjectID], in stack: CoreDataStack) async {
        guard !created.isEmpty else { return }
        AssistantShareAttacher.shared.attach(created, container: stack.container, context: stack.viewContext)
        await AssistantShareAttacher.shared.waitUntilIdle()
    }
}
