import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Practice is a check-in (plan "Simplify the app, round two", Phase 2): the
/// minutes are `WorkCheckIn.durationMinutes` (schema 23), Record Practice
/// writes check-ins, and `PracticeCheckInCopy` turns each retired practice
/// session into check-ins once, however often it runs, and again after a
/// Replace restore that cleared them.
@Suite("Work check-in duration", .serialized)
@MainActor
struct WorkCheckInDurationTests {

    private struct Room {
        let context: NSManagedObjectContext
        let first: CDWorkModel
        let second: CDWorkModel
        let session: NSManagedObject
        let note: CDNote
    }

    /// Two works and an old practice session naming both, with one note on
    /// the session, as an older build left them.
    private func makeRoom() throws -> Room {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = UUID()
        let first = CoreDataTestHelpers.seedWorkModel(in: context, title: "Bead frame", studentID: maya)
        let second = CoreDataTestHelpers.seedWorkModel(in: context, title: "Stamp game", studentID: maya)
        let session = NSEntityDescription.insertNewObject(
            forEntityName: PracticeCheckInCopy.sessionEntityName, into: context
        )
        session.setValue(UUID(), forKey: "id")
        session.setValue(try CoreDataTestHelpers.day("2026-10-20"), forKey: "date")
        session.setValue(900.0, forKey: "duration")
        session.setValue([maya.uuidString] as NSArray, forKey: "studentIDs")
        session.setValue(
            [try #require(first.id).uuidString, try #require(second.id).uuidString] as NSArray,
            forKey: "workItemIDs"
        )
        session.setValue(true, forKey: "madeBreakthrough")
        session.setValue(4, forKey: "practiceQuality")
        session.setValue("Carried twice without help", forKey: "sharedNotes")
        let note = CoreDataTestHelpers.seedNote(in: context, body: "Asked to keep going.")
        note.setValue(session, forKey: "practiceSession")
        #expect(CoreDataTestHelpers.save(context))
        return Room(context: context, first: first, second: second, session: session, note: note)
    }

    private func checkIns(in context: NSManagedObjectContext) -> [CDWorkCheckIn] {
        context.safeFetch(CDFetchRequest(CDWorkCheckIn.self))
    }

    // MARK: - The field

    @Test("durationMinutes is an optional 16-bit number in the model, and schema 23 says so")
    func fieldIsInTheModel() throws {
        let model = try CoreDataStack.sharedModel()
        let attribute = try #require(model.entitiesByName["WorkCheckIn"]?.attributesByName["durationMinutes"])
        #expect(attribute.attributeType == .integer16AttributeType)
        #expect(attribute.isOptional)
        #expect(CoreDataStack.currentSchemaVersion >= 23)
    }

    @Test("Minutes read nil when unset or not above zero, and clamp to the field")
    func durationValue() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let checkIn = CDWorkCheckIn(context: context)
        #expect(checkIn.durationMinutesValue == nil)
        #expect(!checkIn.isPractice)
        checkIn.durationMinutesValue = 25
        #expect(checkIn.durationMinutesValue == 25)
        #expect(checkIn.isPractice)
        checkIn.durationMinutesValue = 0
        #expect(checkIn.durationMinutes == nil)
        checkIn.durationMinutesValue = 100_000
        #expect(checkIn.durationMinutesValue == Int(Int16.max))
    }

    @Test("Recording practice makes a completed check-in with its minutes and a tagged note")
    func recordMakesCheckInAndNote() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let work = CoreDataTestHelpers.seedWorkModel(in: context, studentID: UUID())
        let record = PracticeRecord(
            date: try CoreDataTestHelpers.day("2026-10-21"), minutes: 20, quality: 5,
            helpedPeer: true, needsReteaching: true, notes: "Showed Eli the exchange"
        )
        let checkIn = PracticeCheckIns.record(record, on: work, in: context)
        #expect(CoreDataTestHelpers.save(context))

        #expect(checkIn.status == .completed)
        #expect(checkIn.work === work)
        #expect(checkIn.durationMinutesValue == 20)
        #expect(checkIn.purpose == PracticeCheckIns.purpose)
        #expect(checkIn.practiceSignals == [.helpedPeer, .needsReteaching])
        let note = try #require((checkIn.notes as? Set<CDNote>)?.first)
        #expect(note.work === work)
        #expect(note.body.contains("Showed Eli the exchange"))
        #expect(note.body.hasPrefix("Practice: "))
        #expect(CDWorkCheckIn.practice(onWorkIDs: [try #require(work.id).uuidString], in: context) == [checkIn])
    }

    @Test("Minutes alone make a check-in with no note")
    func recordWithoutWordsHasNoNote() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let work = CoreDataTestHelpers.seedWorkModel(in: context, studentID: UUID())
        let checkIn = PracticeCheckIns.record(PracticeRecord(date: Date(), minutes: 10), on: work, in: context)
        #expect(((checkIn.notes as? Set<CDNote>) ?? []).isEmpty)
    }

    // MARK: - The copy

    @Test("Each old session becomes one check-in per work, and its notes move to the first")
    func copyMakesCheckInsAndRelinksNotes() throws {
        let room = try makeRoom()
        let outcome = try #require(PracticeCheckInCopy.runAndSave(in: room.context))
        #expect(outcome == .init(copied: 2, notesRelinked: 1))

        let made = checkIns(in: room.context)
        #expect(made.count == 2)
        #expect(Set(made.compactMap { $0.work?.objectID }) == [room.first.objectID, room.second.objectID])
        for checkIn in made {
            #expect(checkIn.status == .completed)
            #expect(checkIn.durationMinutesValue == 15)
            #expect(checkIn.date == (try CoreDataTestHelpers.day("2026-10-20")))
            #expect(checkIn.practiceSignals == [.madeBreakthrough])
            #expect(checkIn.noteTags == [PracticeSignal.madeBreakthrough.rawValue])
        }
        #expect(made.contains { $0 === room.note.workCheckIn })
        // The session itself is left as it was, for older builds.
        #expect(!room.session.isDeleted)
        #expect(room.session.value(forKey: "workItemIDs") is [String])
    }

    @Test("A moved note leaves its session, so deleting the session keeps the note")
    func movedNoteSurvivesTheSessionsDeletion() throws {
        let room = try makeRoom()
        _ = try #require(PracticeCheckInCopy.runAndSave(in: room.context))
        #expect(room.note.value(forKey: "practiceSession") == nil)

        room.context.delete(room.session)
        #expect(CoreDataTestHelpers.save(room.context))
        #expect(!room.note.isDeleted)
        #expect(room.note.workCheckIn != nil)
    }

    @Test("A second run adds nothing")
    func copyRunsOnce() throws {
        let room = try makeRoom()
        PracticeCheckInCopy.runAndSave(in: room.context)
        let notes = room.context.safeFetch(CDFetchRequest(CDNote.self)).count
        let again = try #require(PracticeCheckInCopy.runAndSave(in: room.context))
        #expect(again == .init())
        #expect(checkIns(in: room.context).count == 2)
        #expect(room.context.safeFetch(CDFetchRequest(CDNote.self)).count == notes)
    }

    @Test("A session naming no work here copies nothing")
    func copySkipsMissingWork() throws {
        let room = try makeRoom()
        room.session.setValue([UUID().uuidString] as NSArray, forKey: "workItemIDs")
        #expect(CoreDataTestHelpers.save(room.context))
        #expect(PracticeCheckInCopy.runAndSave(in: room.context) == .init())
        #expect(checkIns(in: room.context).isEmpty)
    }

    @Test("The copy waits while the context holds someone else's unsaved change")
    func copyWaitsForUnsavedChanges() throws {
        let room = try makeRoom()
        room.first.title = "Bead frame, golden"
        #expect(PracticeCheckInCopy.runAndSave(in: room.context) == nil)
        #expect(checkIns(in: room.context).isEmpty)
    }

    // MARK: - Restores

    @Test("A Replace restore, of a backup from before the copy or after it, leaves each check-in once")
    func replaceRestoresAddNothingTwice() async throws {
        let room = try makeRoom()
        let before = BackupTestUtil.tempBackupURL()
        let after = BackupTestUtil.tempBackupURL()
        defer {
            BackupTestUtil.cleanup(before)
            BackupTestUtil.cleanup(after)
        }
        try await BackupTestUtil.writeCurrentBackup(from: room.context, to: before)
        PracticeCheckInCopy.runAndSave(in: room.context)
        let ids = Set(checkIns(in: room.context).compactMap(\.id))
        #expect(ids.count == 2)
        try await BackupTestUtil.writeCurrentBackup(from: room.context, to: after)

        // A backup made after the copy brings the check-ins back with their
        // ids; the copy sees them and adds none.
        try await BackupTestUtil.importCurrentBackup(from: after, into: room.context, mode: .replace)
        #expect(Set(checkIns(in: room.context).compactMap(\.id)) == ids)
        #expect(checkIns(in: room.context).count == 2)

        // An older backup has no check-ins: the Replace clears them, and the
        // copy makes the same two again from the sessions still here.
        try await BackupTestUtil.importCurrentBackup(from: before, into: room.context, mode: .replace)
        #expect(Set(checkIns(in: room.context).compactMap(\.id)) == ids)
        #expect(checkIns(in: room.context).count == 2)
        #expect(PracticeCheckInCopy.run(in: room.context) == .init())
    }
}
