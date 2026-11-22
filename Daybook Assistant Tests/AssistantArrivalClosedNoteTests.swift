import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// The arrival-closed note on the Assistant (domain-logic review A1; plan
// "Tide list clean-up 2026-11", Phase 6, D3): her Close Arrival writes one,
// saved and put into the classroom share with the marks, and her Undo and
// Reopen take back every note the day has, the guide's too. It only dates
// the close: whether a day reads closed still comes from its records. The
// notebook's half is `AttendanceArrivalClosedNoteTests`.
@Suite("Assistant arrival-closed note")
@MainActor
struct AssistantArrivalClosedNoteTests {

    private let stack: CoreDataStack
    private var context: NSManagedObjectContext { stack.viewContext }

    init() throws {
        stack = try AssistantTestSupport.makeStack()
    }

    @discardableResult
    private func classOfTwo() -> [CDStudent] {
        let kids = [
            AssistantTestSupport.student("Ari", "Cedar", in: context),
            AssistantTestSupport.student("Maya", "Stone", in: context)
        ]
        #expect(context.safeSave())
        return kids
    }

    /// Every arrival-closed note, from every store.
    private func notes(in context: NSManagedObjectContext? = nil) -> [CDAttendanceEmailSend] {
        let request = CDFetchRequest(CDAttendanceEmailSend.self)
        request.predicate = NSPredicate(format: "channelRaw == %@", AttendanceEmailLog.arrivalClosedChannel)
        return (context ?? self.context).safeFetch(request)
    }

    // MARK: - Writing

    @Test("Close Arrival writes one note with its time, saved; a second close writes none")
    func closeWritesOneNote() throws {
        classOfTwo()
        // A second phone that loaded the day before the first one closed it.
        let other = AssistantTestSupport.viewModel(stack)
        let model = AssistantTestSupport.viewModel(stack)
        let before = Date()
        #expect(model.beginLate() == 2)
        let after = Date()
        #expect(!context.hasChanges, "saved with the marks")

        let note = try #require(notes().first)
        #expect(notes().count == 1)
        let sentAt = try #require(note.sentAt)
        #expect(sentAt >= before && sentAt <= after)
        #expect(note.date == model.date)
        #expect(note.sentBy == CDClassroomMembership.ClassroomRole.assistant.rawValue)
        #expect(AttendanceEmailLog.arrivalClosedAt(on: model.date, in: context) == sentAt)

        #expect(other.beginLate() == 0, "nobody left to mark")
        #expect(other.phase == .late)
        #expect(notes().count == 1)
        #expect(AttendanceEmailLog.arrivalClosedAt(on: model.date, in: context) == sentAt)
        #expect(!context.hasChanges)
    }

    @Test("Her note is never the day's send")
    func noteIsNoSend() {
        classOfTwo()
        let model = AssistantTestSupport.viewModel(stack)
        #expect(model.beginLate() == 2)
        #expect(notes().count == 1)
        model.load()
        #expect(model.frontDesk.latestSend == nil)
        #expect(model.frontDesk.daySends == nil)
        #expect(AttendanceEmailLog.sends(on: model.date, in: context).isEmpty)

        model.frontDesk.recordSend(confirmedByHand: true)
        #expect(AttendanceEmailLog.sends(on: model.date, in: context).count == 1)
        #expect(model.frontDesk.latestSend != nil)
    }

    // MARK: - Every way back

    @Test("Undo and Reopen each take back every note the day has, the guide's too, saved")
    func undoAndReopenLeaveNone() throws {
        classOfTwo()
        let model = AssistantTestSupport.viewModel(stack)
        #expect(model.beginLate() == 2)
        // The guide's Mac closed too before the two synced.
        let guides = CDAttendanceEmailSend(context: context)
        guides.date = model.date
        guides.sentAt = Date().addingTimeInterval(-30)
        guides.sentBy = CDClassroomMembership.ClassroomRole.leadGuide.rawValue
        guides.channelRaw = AttendanceEmailLog.arrivalClosedChannel
        #expect(context.safeSave())
        #expect(notes().count == 2)

        #expect(model.returnToArrival(undo: true))
        #expect(notes().isEmpty)
        #expect(!context.hasChanges)
        #expect(model.phase == .arrival)

        #expect(model.beginLate() == 2)
        #expect(notes().count == 1)
        #expect(model.returnToArrival())
        #expect(notes().isEmpty)
        #expect(!context.hasChanges, "Reopen saves the delete")
        #expect(model.phase == .arrival)
        #expect(model.errorMessage == nil)

        // Back to Late with nobody to mark: the note again, and Reopen takes it.
        #expect(model.beginLate() == 0)
        #expect(model.phase == .late)
        #expect(notes().count == 1)
        #expect(!context.hasChanges)
    }

    @Test("A Reopen whose save fails shows nothing and leaves the day open; the next save takes the note back")
    func failedReopenSaveShowsNothing() throws {
        classOfTwo()
        let model = AssistantTestSupport.viewModel(stack)
        #expect(model.beginLate() == 2)
        #expect(notes().count == 1)
        // An invalid record on a far-off day makes every save fail without
        // appearing on the day being loaded (as `AssistantDayRulesTests`).
        let broken = CDAttendanceRecord(context: context)
        broken.date = try AssistantTestSupport.day("2020-01-06")
        broken.setValue(nil, forKey: "studentID")

        #expect(model.returnToArrival())
        #expect(model.phase == .arrival)
        #expect(model.errorMessage == nil, "a note that won't go says nothing")
        #expect(notes().isEmpty, "deleted, waiting for a save")
        #expect(context.hasChanges)

        context.delete(broken)
        let ari = try #require(model.rows.first { $0.student.firstName == "Ari" })
        model.tap(ari)
        #expect(model.errorMessage == nil)
        #expect(!context.hasChanges, "the tap's save took the delete with it")
        #expect(notes().isEmpty)
        #expect(model.phase == .arrival)
    }

    @Test("A note left behind, with every close-out absence undone, still reads as arrival open")
    func leftoverNoteClosesNothing() throws {
        classOfTwo()
        let defaults = AssistantTestSupport.makeDefaults()
        let model = AssistantTestSupport.viewModel(stack, defaults: defaults)
        #expect(model.beginLate() == 2)

        // The guide undoes the close on the Mac; the note's delete never arrives.
        let guide = CDAttendanceStore(context: context, role: .leadGuide)
        for record in try guide.loadRecords(for: model.date) { #expect(guide.undoAutomaticAbsence(record)) }
        #expect(context.safeSave())
        #expect(notes().count == 1)

        let fresh = AssistantTestSupport.viewModel(stack)
        #expect(fresh.phase == .arrival)
        #expect(!fresh.readsClosed)
        model.load()
        #expect(model.phase == .arrival)
        #expect(!model.readsClosed)
        #expect(model.unmarkedCount == 2)
    }

    // MARK: - The Late rule

    @Test("The Late rule dates the close by the note her Close Arrival wrote")
    func lateRuleReadsTheWrittenNote() throws {
        let kids = classOfTwo()
        let model = AssistantTestSupport.viewModel(stack)
        #expect(model.beginLate() == 2)
        let closedAt = try #require(AttendanceEmailLog.arrivalClosedAt(on: model.date, in: context))
        let records = try CDAttendanceStore(context: context, role: .assistant).loadRecords(for: model.date)
        let ari = try #require(records.first { $0.studentID == kids[0].id?.uuidString })
        let maya = try #require(records.first { $0.studentID == kids[1].id?.uuidString })
        // Maya came in two minutes after the close; Ari's absence reads as
        // made five minutes after it (a later Mark Rest Absent, say).
        maya.status = .tardy
        maya.absenceReasonRaw = AbsenceReason.none.rawValue
        maya.markedAt = closedAt.addingTimeInterval(120)
        ari.markedAt = closedAt.addingTimeInterval(300)
        #expect(context.safeSave())

        /// Whether a phone that first looks now still reads the day closed
        /// once Ari's absence is undone.
        func staysClosed() -> Bool {
            let phone = AssistantTestSupport.viewModel(stack)
            #expect(phone.readsClosed)
            ari.status = .unmarked
            ari.absenceReasonRaw = AbsenceReason.none.rawValue
            defer {
                ari.status = .absent
                ari.absenceReasonRaw = AttendanceDeduplication.automaticAbsenceRaw
            }
            phone.load()
            return phone.readsClosed
        }

        #expect(staysClosed(), "Maya came in after the noted close")
        AttendanceEmailLog.deleteArrivalClosedNotes(on: model.date, role: .assistant, in: context)
        #expect(!staysClosed(), "without the note the close is dated by Ari's absence, after Maya's mark")
    }

    // MARK: - Permissions and the share

    @Test("A View-only phone closes nothing, and writes and deletes no note")
    func viewOnlyWritesNothing() throws {
        classOfTwo()
        let was = ClassroomPermissions.shareIsViewOnly
        defer { ClassroomPermissions.shareIsViewOnly = was }
        let day = AppCalendar.startOfDay(Date())
        let guides = try #require(AttendanceEmailLog.recordArrivalClosed(on: day, role: .leadGuide, in: context))
        #expect(context.safeSave())

        ClassroomPermissions.shareIsViewOnly = true
        let model = AssistantTestSupport.viewModel(stack)
        #expect(model.beginLate() == 0)
        #expect(!model.returnToArrival())
        #expect(AttendanceEmailLog.deleteArrivalClosedNotes(on: day, role: .assistant, in: context) == 0)
        #expect(CDAttendanceStore(context: context, role: .assistant).deleteArrivalClosedNotes(on: day) == 0)
        #expect(notes() == [guides])
        context.delete(guides)
        #expect(context.safeSave())
        #expect(AttendanceEmailLog.recordArrivalClosed(on: day, role: .assistant, in: context) == nil)
        #expect(CDAttendanceStore(context: context, role: .assistant).recordArrivalClosed(on: day) == nil)
        #expect(notes().isEmpty)
        #expect(!context.hasChanges)
    }

    @Test("Her note goes into the shared store, is filed with the save, and her delete leaves another notebook's alone")
    func noteLivesInTheShare() throws {
        let stores = try AssistantTwoStores()
        let (context, shared, own) = (stores.context, stores.shared, stores.own)
        for first in ["Ari", "Maya"] {
            context.assign(AssistantTestSupport.student(first, "Cedar", in: context), to: shared)
        }
        // A notebook of her own on the same Apple Account noted its own close.
        let ownNote = CDAttendanceEmailSend(context: context)
        context.assign(ownNote, to: own)
        ownNote.date = AppCalendar.startOfDay(Date())
        ownNote.sentAt = Date().addingTimeInterval(-600)
        ownNote.channelRaw = AttendanceEmailLog.arrivalClosedChannel
        #expect(context.safeSave())

        // The class's day has no close yet: her own notebook's doesn't count.
        let store = CDAttendanceStore(context: context, role: .assistant)
        let note = try #require(store.recordArrivalClosed(on: ownNote.date ?? Date()))
        #expect(AssistantSave.recordsToFile(created: [], in: context).contains { $0 === note }, "filed by the save")
        #expect(SiriHost.recordsToFile(created: [], in: context).contains { $0 === note }, "and by Siri's")
        #expect(context.safeSave())
        #expect(note.objectID.persistentStore === shared)
        #expect(notes(in: context).count == 2)

        #expect(store.deleteArrivalClosedNotes(on: ownNote.date ?? Date()) == 1)
        #expect(context.safeSave())
        #expect(notes(in: context).map(\.objectID) == [ownNote.objectID])
    }
}

/// The Assistant's stack with the classroom share's store beside its own, as
/// on a phone whose Apple Account also keeps a notebook.
@MainActor
struct AssistantTwoStores {
    let stack: CoreDataStack
    let shared: NSPersistentStore
    let own: NSPersistentStore
    var context: NSManagedObjectContext { stack.viewContext }

    init() throws {
        stack = try AssistantTestSupport.makeStack()
        let coordinator = try #require(stack.viewContext.persistentStoreCoordinator)
        let shared = try coordinator.addPersistentStore(
            type: .inMemory,
            configuration: CoreDataStack.sharedConfiguration,
            at: URL(fileURLWithPath: "/dev/null/shared-\(UUID().uuidString)")
        )
        self.shared = shared
        own = try #require(coordinator.persistentStores.first { $0 !== shared })
    }
}
