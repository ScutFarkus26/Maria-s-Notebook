import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

// The arrival-closed note (domain-logic review A1; plan "Tide list clean-up
// 2026-11", Phase 6, D3): the notebook writes one where arrival closes and
// takes it back on every way back to Arrival. It only dates the close:
// whether a day reads closed still comes from its records. The Assistant's
// half is `AssistantArrivalClosedNoteTests`.
@Suite("Arrival-closed note")
@MainActor
struct AttendanceArrivalClosedNoteTests {

    private let stack: CoreDataStack
    private let defaults: UserDefaults
    private let today = AppCalendar.startOfDay(Date())

    init() throws {
        stack = try CoreDataTestHelpers.makeInMemoryStack()
        defaults = Self.makeDefaults()
    }

    private var context: NSManagedObjectContext { stack.viewContext }

    /// A device of its own: what it remembers of the Late phase.
    private static func makeDefaults() -> UserDefaults {
        let suite = "AttendanceArrivalClosedNoteTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @discardableResult
    private func student(_ first: String, in context: NSManagedObjectContext? = nil) -> CDStudent {
        let student = CDStudent(context: context ?? self.context)
        student.id = UUID()
        student.firstName = first
        student.lastName = "Stone"
        student.dateStarted = Calendar.current.date(byAdding: .year, value: -1, to: today)
        return student
    }

    private func model(
        _ students: [CDStudent], defaults: UserDefaults? = nil, in context: NSManagedObjectContext? = nil
    ) -> AttendanceViewModel {
        let model = AttendanceViewModel(selectedDate: today, defaults: defaults ?? self.defaults)
        model.load(students: students, modelContext: context ?? self.context)
        return model
    }

    /// The day's arrival-closed notes, from every store.
    private func notes(in context: NSManagedObjectContext? = nil) -> [CDAttendanceEmailSend] {
        let request = CDFetchRequest(CDAttendanceEmailSend.self)
        request.predicate = NSPredicate(format: "channelRaw == %@", AttendanceEmailLog.arrivalClosedChannel)
        return (context ?? self.context).safeFetch(request)
    }

    // MARK: - Writing

    @Test("Close Arrival writes one note with its time; a second close writes none")
    func closeWritesOneNote() throws {
        let kids = [student("Maya"), student("Ari")]
        // A second device that loaded the day before the first one closed it.
        let other = model(kids, defaults: Self.makeDefaults())
        let roll = model(kids)
        let before = Date()
        #expect(roll.closeArrival(modelContext: context)?.records.count == 2)
        let after = Date()
        try context.save()

        let note = try #require(notes().first)
        #expect(notes().count == 1)
        let sentAt = try #require(note.sentAt)
        #expect(sentAt >= before && sentAt <= after)
        #expect(note.date == today)
        #expect(note.sentBy == CDClassroomMembership.ClassroomRole.leadGuide.rawValue)
        #expect(AttendanceEmailLog.arrivalClosedAt(on: today, in: context) == sentAt)

        // Its close finds nobody left to mark and writes no second note.
        #expect(other.closeArrival(modelContext: context)?.records.isEmpty == true)
        #expect(notes().count == 1)
        #expect(AttendanceEmailLog.arrivalClosedAt(on: today, in: context) == sentAt)
        // Nor does Mark Rest Absent once arrival is closed.
        roll.markUnmarkedAbsent(modelContext: context)
        #expect(notes().count == 1)
        // The writer itself: once a day.
        #expect(AttendanceEmailLog.recordArrivalClosed(on: today, role: .assistant, in: context) == nil)
        #expect(notes().count == 1)
    }

    @Test("Undo of a Reset Day closes the day again and writes its note again")
    func undoResetWritesTheNote() throws {
        let roll = model([student("Maya"), student("Ari")])
        #expect(roll.closeArrival(modelContext: context) != nil)
        try context.save()
        let closedAt = try #require(AttendanceEmailLog.arrivalClosedAt(on: today, in: context))
        let reset = try #require(roll.resetDay(modelContext: context))
        try context.save()
        #expect(notes().isEmpty, "Reset Day leaves none")

        #expect(roll.undoReset(reset, modelContext: context) == 2)
        try context.save()
        #expect(roll.phase == .late)
        #expect(notes().count == 1)
        #expect(AttendanceEmailLog.arrivalClosedAt(on: today, in: context) == closedAt, "the close's first time")
    }

    @Test("A note is never the day's send, and a send beside it still counts once")
    func noteIsNoSend() throws {
        let roll = model([student("Maya")])
        #expect(roll.closeArrival(modelContext: context) != nil)
        try context.save()
        #expect(notes().count == 1)
        #expect(AttendanceEmailLog.sends(on: today, in: context).isEmpty)
        #expect(AttendanceEmailLog.latestSend(on: today, in: context) == nil)
        #expect(AttendanceEmailLog.daySends(on: today, in: context) == nil)
        #expect(AttendanceEmailLog.dayRecords(on: today, in: context).sends.isEmpty)
        #expect(AttendanceEmailLog.changesSinceReported(on: today, in: context) == nil)

        AttendanceEmailLog.recordSend(on: today, role: .leadGuide, in: context)
        #expect(AttendanceEmailLog.sends(on: today, in: context).count == 1)
        #expect(AttendanceEmailLog.dayRecords(on: today, in: context).sends.count == 1)
    }

    // MARK: - Every way back

    @Test("Undo, Reopen and Reset Day each leave no note for the day, another device's included")
    func everyWayBackLeavesNone() throws {
        let kids = [student("Maya"), student("Ari")]

        // Undo.
        let roll = model(kids)
        let undo = try #require(roll.closeArrival(modelContext: context))
        try context.save()
        // An assistant's phone closed too before the two synced.
        let second = CDAttendanceEmailSend(context: context)
        second.date = today
        second.sentAt = Date().addingTimeInterval(30)
        second.channelRaw = AttendanceEmailLog.arrivalClosedChannel
        try context.save()
        #expect(notes().count == 2)
        #expect(roll.undoCloseArrival(undo, modelContext: context) == 2)
        try context.save()
        #expect(notes().isEmpty)

        // Reopen.
        #expect(roll.closeArrival(modelContext: context) != nil)
        try context.save()
        #expect(notes().count == 1)
        roll.reopenArrival(modelContext: context)
        try context.save()
        #expect(notes().isEmpty)

        // Reset Day, from Late and from Arrival (a note another device left).
        #expect(roll.closeArrival(modelContext: context) != nil)
        try context.save()
        #expect(roll.resetDay(modelContext: context) != nil)
        try context.save()
        #expect(notes().isEmpty)
        AttendanceEmailLog.recordArrivalClosed(on: today, role: .leadGuide, in: context)
        let maya = try #require(roll.rows.first { $0.shortName == "Maya" })
        #expect(roll.setStatus(.present, for: maya, modelContext: context))
        try context.save()
        #expect(roll.phase == .arrival)
        #expect(roll.resetDay(modelContext: context) != nil)
        try context.save()
        #expect(notes().isEmpty)
        #expect(!context.hasChanges)
    }

    @Test("A note left behind, with every close-out absence undone, still reads as arrival open")
    func leftoverNoteClosesNothing() throws {
        let kids = [student("Maya"), student("Ari")]
        let roll = model(kids)
        #expect(roll.closeArrival(modelContext: context)?.records.count == 2)
        try context.save()

        // Another device undoes the close; its note's delete never arrives.
        let phone = CDAttendanceStore(context: context, role: .leadGuide)
        for record in try phone.loadRecords(for: today) { #expect(phone.undoAutomaticAbsence(record)) }
        try context.save()
        #expect(notes().count == 1)

        // A device that never saw the close, and the one that made it.
        let fresh = model(kids, defaults: Self.makeDefaults())
        #expect(fresh.phase == .arrival)
        #expect(!fresh.readsClosed)
        #expect(try !CDAttendanceStore(context: context).arrivalClosed(on: today, defaults: Self.makeDefaults()))
        roll.load(students: kids, modelContext: context)
        #expect(roll.phase == .arrival)
        #expect(!roll.readsClosed)

        // A note with no records at all closes nothing either.
        let empty = try CoreDataTestHelpers.makeContext()
        AttendanceEmailLog.recordArrivalClosed(on: today, role: .leadGuide, in: empty)
        #expect(try !CDAttendanceStore(context: empty).arrivalClosed(on: today, defaults: Self.makeDefaults()))
    }

    // MARK: - The Late rule

    @Test("The Late rule dates the close by the note Close Arrival wrote")
    func lateRuleReadsTheWrittenNote() throws {
        let maya = student("Maya"), ari = student("Ari")
        let roll = model([maya, ari])
        #expect(roll.closeArrival(modelContext: context)?.records.count == 2)
        try context.save()
        let closedAt = try #require(AttendanceEmailLog.arrivalClosedAt(on: today, in: context))
        let records = try CDAttendanceStore(context: context).loadRecords(for: today)
        let mayaRecord = try #require(records.first { $0.studentID == maya.id?.uuidString })
        let ariRecord = try #require(records.first { $0.studentID == ari.id?.uuidString })
        // Maya came in two minutes after the close; Ari's absence reads as
        // made five minutes after it (a later Mark Rest Absent, say).
        mayaRecord.status = .tardy
        mayaRecord.absenceReasonRaw = AbsenceReason.none.rawValue
        mayaRecord.markedAt = closedAt.addingTimeInterval(120)
        ariRecord.markedAt = closedAt.addingTimeInterval(300)
        try context.save()

        /// Whether a device that first looks now still reads the day closed
        /// once Ari's absence is undone.
        func staysClosed() throws -> Bool {
            let device = Self.makeDefaults()
            let store = CDAttendanceStore(context: context, role: .leadGuide)
            #expect(try store.arrivalClosed(on: today, defaults: device))
            ariRecord.status = .unmarked
            ariRecord.absenceReasonRaw = AbsenceReason.none.rawValue
            defer {
                ariRecord.status = .absent
                ariRecord.absenceReasonRaw = AttendanceDeduplication.automaticAbsenceRaw
            }
            return try store.arrivalClosed(on: today, defaults: device)
        }

        #expect(try staysClosed(), "Maya came in after the noted close")
        AttendanceEmailLog.deleteArrivalClosedNotes(on: today, role: .leadGuide, in: context)
        #expect(try !staysClosed(), "without the note the close is dated by Ari's absence, after Maya's mark")
    }

    // MARK: - Permissions and the share

    @Test("A View-only assistant writes and deletes no note; the guide still can")
    func viewOnlyWritesNothing() throws {
        let was = ClassroomPermissions.shareIsViewOnly
        defer { ClassroomPermissions.shareIsViewOnly = was }
        let guideNote = try #require(AttendanceEmailLog.recordArrivalClosed(on: today, role: .leadGuide, in: context))
        try context.save()

        ClassroomPermissions.shareIsViewOnly = true
        #expect(AttendanceEmailLog.deleteArrivalClosedNotes(on: today, role: .assistant, in: context) == 0)
        #expect(CDAttendanceStore(context: context, role: .assistant).deleteArrivalClosedNotes(on: today) == 0)
        #expect(notes() == [guideNote])
        AttendanceEmailLog.deleteArrivalClosedNotes(on: today, role: .leadGuide, in: context)
        try context.save()
        #expect(AttendanceEmailLog.recordArrivalClosed(on: today, role: .assistant, in: context) == nil)
        #expect(CDAttendanceStore(context: context, role: .assistant).recordArrivalClosed(on: today) == nil)
        #expect(notes().isEmpty)
        #expect(!context.hasChanges)

        ClassroomPermissions.shareIsViewOnly = false
        #expect(AttendanceEmailLog.recordArrivalClosed(on: today, role: .assistant, in: context) != nil)
    }

    @Test("A locked day keeps its note as it is: no write, no delete")
    func lockedDayKeepsItsNote() throws {
        let note = try #require(AttendanceEmailLog.recordArrivalClosed(on: today, role: .leadGuide, in: context))
        #expect(AttendanceDayLocks.setLocked(true, for: today, role: .leadGuide, in: context))
        try context.save()
        let store = CDAttendanceStore(context: context, role: .leadGuide)
        #expect(store.deleteArrivalClosedNotes(on: today) == 0)
        #expect(notes() == [note])
        #expect(AttendanceDayLocks.setLocked(false, for: today, role: .leadGuide, in: context))
        #expect(store.deleteArrivalClosedNotes(on: today) == 1)
    }

    @Test("The guide's note is a classroom insert into his private store, as SharedStoreOrphanGuard reads a save")
    func guideNoteReachesTheOrphanGuard() throws {
        let split = try CoreDataTestHelpers.makeSplitStoreContext()
        let stores = split.persistentStoreCoordinator?.persistentStores ?? []
        let privateStore = try #require(stores.first { $0.configurationName == CoreDataStack.privateConfiguration })
        let sharedStore = try #require(stores.first { $0.configurationName == CoreDataStack.sharedConfiguration })
        let kids = [student("Maya", in: split)]
        for kid in kids { split.assign(kid, to: privateStore) }
        #expect(split.safeSave())
        let watch = InsertWatch()
        let token = NotificationCenter.default.addObserver(of: split, for: .didSave) { message in
            watch.inserted += SharedStoreOrphanGuard.classroomInserts(message.inserted, privateStore: privateStore)
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let roll = model(kids, in: split)
        #expect(roll.closeArrival(modelContext: split)?.records.count == 1)
        #expect(split.safeSave())
        let note = try #require(notes(in: split).first)
        #expect(note.objectID.persistentStore === privateStore)
        #expect(watch.inserted.contains(note.objectID), "the orphan guard puts it into the classroom share")

        // A notebook joined as an assistant writes into the shared store,
        // where the assistant's filing takes it (`AssistantRoleShareFiling`).
        roll.reopenArrival(modelContext: split)
        #expect(split.safeSave())
        #expect(notes(in: split).isEmpty)
        let assistants = try #require(
            AttendanceEmailLog.recordArrivalClosed(on: today, role: .assistant, in: split)
        )
        #expect(split.safeSave())
        #expect(assistants.objectID.persistentStore === sharedStore)
    }
}

/// What a `.didSave` observer saw.
private final class InsertWatch {
    var inserted: [NSManagedObjectID] = []
}

// MARK: - Siri's Undo

// In `SiriAttendanceTests`, so it runs one at a time with them: Siri's undo
// memory is one standard-defaults key.
extension SiriAttendanceTests {

    @Test("Siri's Undo of a Close Arrival takes the day's note back, saved")
    func siriUndoTakesTheNoteBack() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let day = try CoreDataTestHelpers.day("2031-03-17")
        defer {
            SiriAttendanceChange.forget()
            AttendanceLatePhase.setLate(false, on: day)
        }
        let context = stack.viewContext
        // The close Siri made: nobody left to mark, the note in the share.
        AttendanceEmailLog.recordArrivalClosed(on: day, role: .leadGuide, in: context)
        #expect(context.safeSave())
        AttendanceLatePhase.setLate(true, on: day)
        SiriAttendanceChange(day: day, marks: [], summary: "closing arrival", closedArrival: true).remember()

        var siri = SiriAttendance(stack: stack, role: .leadGuide, today: day.addingTimeInterval(9 * 3_600))
        siri.parentLocker = { nil }
        #expect(try await siri.undoLast() == "Done. Arrival is open again.")
        #expect(AttendanceEmailLog.arrivalClosedAt(on: day, in: context) == nil)
        #expect(!context.hasChanges, "the delete is saved")
        #expect(!AttendanceLatePhase.isLate(on: day))
    }
}
