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

    /// The children on the roll, in the grid's order.
    static func roster(in context: NSManagedObjectContext) -> [CDStudent] {
        let request = CDFetchRequest(CDStudent.self)
        request.sortDescriptors = [
            NSSortDescriptor(key: "firstName", ascending: true),
            NSSortDescriptor(key: "lastName", ascending: true)
        ]
        return context.safeFetch(request).filter(\.isEnrolled)
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
