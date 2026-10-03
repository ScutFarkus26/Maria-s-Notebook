import CoreData

/// The Assistant's half of the Siri layer: the shared files (the student
/// entity, `SiriAttendance`, the attendance intents) reach the app only
/// through `SiriHost`, which Cosmic Daybook defines with the same shape.
@MainActor
enum SiriHost {
    static func stack() throws -> CoreDataStack {
        try AssistantStack.shared()
    }

    /// Until an invitation is accepted there is no class to mark.
    static func checkReady(in context: NSManagedObjectContext) throws {
        if AssistantSampleClass.isRequested { return }
        let request = CDClassroomMembership.ownRowsRequest()
        request.fetchLimit = 1
        guard context.safeFetchFirst(request) != nil else {
            throw SiriAttendanceError.notReady("Open Daybook Assistant and join your class first.")
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
    /// arrives is tardy, exactly as a tap during Late marks them.
    static func statusForHere(on day: Date, store: CDAttendanceStore) -> AttendanceStatus {
        AttendanceLatePhase.isLate(on: day, closedAnywhere: (try? store.arrivalClosed(on: day)) == true)
            ? .tardy : .present
    }

    static func arrivalReopened(on day: Date) {
        AttendanceLatePhase.reopen(on: day)
    }

    /// New marks go into the classroom share explicitly, as the grid's do.
    static func didSave(created: [NSManagedObjectID], in stack: CoreDataStack) async {
        guard !created.isEmpty else { return }
        AssistantShareAttacher.shared.attach(created, container: stack.container, context: stack.viewContext)
        await AssistantShareAttacher.shared.waitUntilIdle()
    }
}
