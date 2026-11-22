import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// Siri's half of the Assistant's arrival-closed note (plan "Tide list
// clean-up 2026-11", Phase 6): her Close Arrival writes one, saved and
// filed with the marks, and her Undo takes it back. The grid's half is
// `AssistantArrivalClosedNoteTests`.

/// A class on a Monday of its own, so its Late days don't meet other tests'.
@MainActor
private struct NoteClass {
    let stack: CoreDataStack
    let day: Date
    var context: NSManagedObjectContext { stack.viewContext }

    init(_ firsts: [String], day iso: String = "2031-03-24") throws {
        stack = try AssistantTestSupport.makeStack()
        day = try AssistantTestSupport.day(iso)
        for first in firsts { AssistantTestSupport.student(first, "Cedar", in: stack.viewContext) }
        #expect(stack.viewContext.safeSave())
        forget()
    }

    func siri() -> SiriAttendance {
        var siri = SiriAttendance(stack: stack, role: .assistant, today: day.addingTimeInterval(9 * 3_600))
        siri.parentLocker = { nil }
        return siri
    }

    var notes: [CDAttendanceEmailSend] {
        let request = CDFetchRequest(CDAttendanceEmailSend.self)
        request.predicate = NSPredicate(format: "channelRaw == %@", AttendanceEmailLog.arrivalClosedChannel)
        return context.safeFetch(request)
    }

    /// Siri's memories and this day's Late, cleared.
    func forget() {
        SiriAttendanceChange.forget()
        AttendanceLatePhase.setLate(false, on: day)
    }
}

// In `AssistantSiriTests`, so they run one at a time with it: they write the
// app's own Late, Siri memories and View only.
extension AssistantSiriTests {

    @Test("Siri's Close Arrival writes one note, saved; her Undo takes it back, saved")
    func siriCloseWritesTheNote() async throws {
        let cls = try NoteClass(["Ari", "Maya"])
        defer { cls.forget() }
        let siri = cls.siri()
        let before = Date()
        #expect(try await AssistantSiriCommands.closeArrival(siri) == 2)
        let note = try #require(cls.notes.first)
        #expect(cls.notes.count == 1)
        #expect((note.sentAt ?? .distantPast) >= before)
        #expect(note.date == cls.day)
        #expect(!cls.context.hasChanges, "saved with the marks")
        await #expect(throws: SiriAttendanceError.self) { try await AssistantSiriCommands.closeArrival(siri) }
        #expect(cls.notes.count == 1)

        #expect(try await siri.undoLast() == "Done. Arrival is open again.")
        #expect(cls.notes.isEmpty)
        #expect(!cls.context.hasChanges, "the delete is saved")
    }

    @Test("Siri's Close Arrival with everyone marked still notes the close, saved, and its Undo takes it back")
    func siriEmptyCloseWritesTheNote() async throws {
        let cls = try NoteClass(["Ari"])
        defer { cls.forget() }
        let siri = cls.siri()
        let ari = try #require(cls.context.safeFetch(CDFetchRequest(CDStudent.self)).first)
        try await siri.mark(ari, as: .present)

        #expect(try await AssistantSiriCommands.closeArrival(siri) == 0)
        #expect(cls.notes.count == 1)
        #expect(!cls.context.hasChanges)
        #expect(try await siri.undoLast() == "Done. Arrival is open again.")
        #expect(cls.notes.isEmpty)
        #expect(!cls.context.hasChanges)
    }

    @Test("Siri's Close Arrival with everyone marked whose note won't save drops it and still closes")
    func siriEmptyCloseDropsAnUnsavedNote() async throws {
        let cls = try NoteClass(["Ari"])
        defer { cls.forget() }
        var siri = cls.siri()
        let ari = try #require(cls.context.safeFetch(CDFetchRequest(CDStudent.self)).first)
        try await siri.mark(ari, as: .present)

        siri.save = { _ in false }
        #expect(try await AssistantSiriCommands.closeArrival(siri) == 0)
        #expect(cls.notes.isEmpty)
        // What the end of the run loop's event does: a deleted insert leaves.
        let before = Self.pending(in: cls.context)
        cls.context.processPendingChanges()
        let pending = Self.pending(in: cls.context)
        #expect(pending.isEmpty, "not left for another save: \(pending); before processing: \(before)")
        #expect(AttendanceLatePhase.isLate(on: cls.day))
    }

    /// The context's unsaved changes, by entity: inserted, updated, deleted.
    private static func pending(in context: NSManagedObjectContext) -> [String] {
        context.insertedObjects.map { "+\($0.entity.name ?? "?")" }
            + context.updatedObjects.map { "~\($0.entity.name ?? "?")" }
            + context.deletedObjects.map { "-\($0.entity.name ?? "?")" }
    }

    @Test("Siri's Close Arrival whose save fails leaves no note, and arrival open")
    func siriFailedCloseLeavesNoNote() async throws {
        let cls = try NoteClass(["Ari", "Maya"])
        defer { cls.forget() }
        var siri = cls.siri()
        siri.save = { _ in false }
        await #expect(throws: SiriAttendanceError.self) { try await AssistantSiriCommands.closeArrival(siri) }
        #expect(cls.notes.isEmpty)
        #expect(!AttendanceLatePhase.isLate(on: cls.day))
    }

    @Test("On a View-only phone Siri's Close Arrival writes no note")
    func siriViewOnlyWritesNoNote() async throws {
        let cls = try NoteClass(["Ari", "Maya"])
        defer { cls.forget() }
        let siri = cls.siri()
        let was = ClassroomPermissions.shareIsViewOnly
        ClassroomPermissions.shareIsViewOnly = true
        defer { ClassroomPermissions.shareIsViewOnly = was }
        await #expect(throws: SiriAttendanceError.self) { try await AssistantSiriCommands.closeArrival(siri) }
        #expect(cls.notes.isEmpty)
        #expect(!cls.context.hasChanges)
    }
}
