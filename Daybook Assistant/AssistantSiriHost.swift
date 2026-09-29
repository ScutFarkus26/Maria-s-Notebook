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
        #if DEBUG
        if AssistantSampleClass.isRequested { return }
        #endif
        let request = CDClassroomMembership.ownRowsRequest()
        request.fetchLimit = 1
        guard context.safeFetchFirst(request) != nil else {
            throw SiriAttendanceError.notReady("Open Daybook Assistant and join your class first.")
        }
    }

    /// Every enrolled child, for matching a spoken name (`StudentEntityQuery`).
    /// Commands that act on the whole class use the day's roll instead
    /// (`AssistantDayRoll`), which leaves out a child who hasn't started yet.
    static func roster(in context: NSManagedObjectContext) -> [CDStudent] {
        let request = AssistantDayRoll.classroomStudents(in: context)
        request.sortDescriptors = CDStudent.sortByName
        return context.safeFetch(request).filter(\.isEnrolled)
    }

    /// Nothing the Assistant does is about a child who has left, and on a
    /// locked phone the answer would tell anyone nearby that she has.
    static let findsFormerStudents = false

    /// Siri names children as the grid does: first names, with an initial
    /// only where two share one. Here and late answer on a locked phone,
    /// where a full name tells anyone nearby more than was said.
    static func displayNames(for students: [CDStudent]) -> [NSManagedObjectID: String] {
        AssistantAttendanceViewModel.gridNames(for: students)
    }

    /// Hardcoded, as in the grid: this app is only ever used by an assistant.
    static let role: CDClassroomMembership.ClassroomRole? = .assistant

    /// Once arrival has closed on this phone, a child who arrives is tardy,
    /// exactly as a tap during Late marks them.
    static func statusForHere(on day: Date) -> AttendanceStatus {
        AssistantAttendanceViewModel.LatePhaseMemory.isLate(on: day) ? .tardy : .present
    }

    static func arrivalReopened(on day: Date) {
        AssistantAttendanceViewModel.LatePhaseMemory.setLate(false, on: day)
    }

    /// New marks go into the classroom share explicitly, as the grid's do.
    static func didSave(created: [NSManagedObjectID], in stack: CoreDataStack) async {
        guard !created.isEmpty else { return }
        await CDAttendanceStore.attachNewRecordsToClassroomShare(
            created, container: stack.container, pinContext: stack.viewContext
        )
    }
}
