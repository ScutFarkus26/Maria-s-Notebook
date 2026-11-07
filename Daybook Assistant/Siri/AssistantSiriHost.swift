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

    /// What Siri says while the guide has her as View only: the same words
    /// as the grid's notice.
    nonisolated static let viewOnlyMessage = AssistantSyncStatusView.viewOnlyMessage

    /// Until an invitation is accepted there is no class to mark.
    static func checkReady(in context: NSManagedObjectContext) throws {
        if AssistantSampleClass.isRequested { return }
        let request = CDClassroomMembership.ownRowsRequest()
        request.fetchLimit = 1
        guard context.safeFetchFirst(request) != nil else {
            throw SiriAttendanceError.notReady("Open the Assistant app and join your class first.")
        }
    }

    /// The child Siri marks for a spoken name's `id`: the class's own row,
    /// from the classroom share, as the grid reads (`AssistantDayRoll`). On
    /// an Apple Account that also keeps a notebook of its own, the private
    /// store can hold a row with the same id, and Siri could pick it: a
    /// full name said aloud on a locked phone, or a current child refused
    /// because that copy's dates didn't fit (bug hunt 2026-11-06, #13). A
    /// child who synced in twice is the grid's copy, the first by name.
    static func student(id: UUID, in context: NSManagedObjectContext) -> CDStudent? {
        let request = AssistantDayRoll.classroomStudents(in: context)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.sortDescriptors = CDStudent.sortByName
        return context.safeFetchFirst(request)
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

    /// A child who has left is "not found": the Assistant knows no former
    /// children, and on a locked phone "isn't in the class anymore" would
    /// tell anyone nearby that she has left (bug hunt 2026-10-20, #29).
    static let refusesFormerByName = false

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
    /// afterwards was ignored here. The ParentLocker send Siri's Close
    /// Arrival left waiting doesn't go either (bug hunt 2026-10-13
    /// afternoon, H2; `AssistantSiriCommands.undoCloseSend`).
    ///
    /// `reopen`: arrival had been reopened here before Siri closed it, so
    /// it's reopened again, as the bar's Reopen left it. Going by the records
    /// found the first close's absences and stayed in Late, while Siri said
    /// "Arrival is open again" (bug hunt 2026-11-06, #3).
    static func closeArrivalUndone(on day: Date, reopen: Bool) {
        if reopen {
            AttendanceLatePhase.reopen(on: day)
        } else {
            AttendanceLatePhase.setLate(false, on: day)
        }
        AssistantSiriCommands.undoCloseSend(on: day, sync: ParentLockerSync.current)
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

    /// How long Siri's keep-alive waits for the share attach: the same 25 s
    /// as leaving the app (`UnsentChangesKeepAlive.limit`), inside the 30 s
    /// iOS allows in the background.
    static let attachWaitLimit = UnsentChangesKeepAlive.limit

    /// What a Siri save hands `didSave`, read before the save: `created`,
    /// then every other classroom-share record the save inserts, as the
    /// grid's saves file them (`AssistantSave.recordsToFile`). Siri's saves
    /// used to file only Siri's own, so a record another screen left in the
    /// context was saved into no share (bug hunt 2026-11-03 #25).
    static func recordsToFile(created: [NSManagedObject], in context: NSManagedObjectContext) -> [NSManagedObject] {
        AssistantSave.recordsToFile(created: created, in: context)
    }

    /// New marks go into the classroom share explicitly, as the grid's do.
    /// Siri's keep-alive (`SiriSyncKeepAlive`) waits for the attach at most
    /// `limit`: `share(_:to:)` can block for good, and until 2026-10-10 the
    /// wait for it held the app awake until iOS cut it off. Only the waiting
    /// ends: an attach still running carries on while the app does, and what
    /// hasn't gone in stays on the attacher's list for its next try (a save,
    /// a return to the app, the next launch). Tests pass `attacher` and `sleep`.
    static func didSave(
        created: [NSManagedObjectID],
        in stack: CoreDataStack,
        attacher: AssistantShareAttacher = .shared,
        limit: Duration = SiriHost.attachWaitLimit,
        sleep: @escaping UnsentChangesKeepAlive.Sleep = { try await Task.sleep(for: $0) }
    ) async {
        guard !created.isEmpty else { return }
        attacher.attach(created, container: stack.container, context: stack.viewContext)
        await UnsentChangesKeepAlive.wait(atMost: limit, sleep: sleep) { await attacher.waitUntilIdle() }
    }
}
