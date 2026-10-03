import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// Leaving Early… on the grid sets a pickup time without marking anyone, and
// the reminder comes the set lead time before it, only for children still
// due to go.
@Suite("Early pickup")
@MainActor
struct EarlyPickupReminderTests {

    private let today = Calendar.current.startOfDay(for: Date())

    private func clock(_ hour: Int, _ minute: Int, on day: Date? = nil) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day ?? today) ?? today
    }

    @Test("The reminder comes the lead time before, and not once that has passed")
    func fireDate() {
        let pickup = clock(13, 30)
        #expect(EarlyPickupReminder.fireDate(for: pickup, leadMinutes: 10, now: clock(9, 0)) == clock(13, 20))
        #expect(EarlyPickupReminder.fireDate(for: pickup, leadMinutes: 10, now: clock(13, 25)) == nil)
    }

    @Test("The guide's note becomes one sentence, never ending in two stops")
    func noteSentence() {
        #expect(EarlyPickupReminder.sentence("Dentist") == "Dentist.")
        #expect(EarlyPickupReminder.sentence("Dentist.") == "Dentist.")
        #expect(EarlyPickupReminder.sentence("Grandma picking up! ") == "Grandma picking up!")

        let pickup = EarlyPickupReminder.Pickup(studentID: "a", name: "Maya", leavesAt: clock(13, 30), note: "Dentist.")
        let reminder = EarlyPickupReminder.reminders(for: [pickup], leadMinutes: 10, now: clock(9, 0), isSample: false)
        #expect(reminder.first?.body == "Dentist. Mark Left Early when they go.")
    }

    @Test("Setting a pickup on the grid marks nothing; removing it leaves no blank record")
    func gridSetsAndRemoves() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        AssistantTestSupport.student("Maya", "Stone", in: context)
        _ = context.safeSave()
        let model = AssistantTestSupport.viewModel(stack)
        let row = try #require(model.rows.first)
        #expect(model.allowsPickup(for: row))

        // Removing a time that was never set creates nothing.
        model.setPickup(nil, for: row)
        #expect(context.safeFetch(CDFetchRequest(CDAttendanceRecord.self)).isEmpty)
        #expect(model.pickupEdits == 0)

        model.setPickup(clock(13, 30), for: row)
        let updated = try #require(model.rows.first)
        #expect(updated.leavesAt == clock(13, 30))
        #expect(updated.status == .unmarked)
        #expect(model.pickupEdits == 1)

        model.setStatus(.leftEarly, for: updated)
        let gone = try #require(model.rows.first)
        #expect(!model.allowsPickup(for: gone))
    }

    @Test("Only children still due to go get a reminder, by their short names")
    func pendingPickups() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let maya = AssistantTestSupport.student("Maya", "Stone", in: context)
        let ari = AssistantTestSupport.student("Ari", "Cedar", in: context)
        let etty = AssistantTestSupport.student("Etty", "Gold", in: context)
        let tomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: today))
        let store = CDAttendanceStore(context: context, role: .assistant)

        let mayaToday = try #require(try store.ensureRecord(for: maya, on: today))
        store.updateLeavesAt(mayaToday, to: clock(13, 30))
        store.updateNote(mayaToday, to: "dentist")
        let ariToday = try #require(try store.ensureRecord(for: ari, on: today))
        store.updateLeavesAt(ariToday, to: clock(12, 0))
        store.updateStatus(ariToday, to: .leftEarly)
        let ettyTomorrow = try #require(try store.ensureRecord(for: etty, on: tomorrow))
        store.updateLeavesAt(ettyTomorrow, to: clock(11, 0, on: tomorrow))
        _ = context.safeSave()

        let pickups = EarlyPickupReminder.pendingPickups(in: context, now: clock(9, 0))
        #expect(pickups.map(\.name) == [maya.shortName, etty.shortName])
        #expect(pickups.first?.note == "dentist")

        // After Maya's time, only tomorrow's is still to come.
        let later = EarlyPickupReminder.pendingPickups(in: context, now: clock(14, 0))
        #expect(later.map(\.name) == [etty.shortName])
    }

    @Test("The sample class's pickups are found, under their own prefix")
    func sampleClassPickups() throws {
        let stack = try AssistantSampleClass.makeStack()
        let context = stack.viewContext
        let students = context.safeFetch(CDFetchRequest(CDStudent.self))
        let maya = try #require(students.first { $0.firstName == "Maya" })
        let store = CDAttendanceStore(context: context, role: .assistant)
        let record = try #require(try store.ensureRecord(for: maya, on: today))
        store.updateLeavesAt(record, to: clock(13, 30))
        _ = context.safeSave()

        let pickups = EarlyPickupReminder.pendingPickups(in: context, now: clock(9, 0))
        #expect(pickups.map(\.name) == [maya.shortName])

        let id = try #require(maya.id?.uuidString)
        let sampleID = EarlyPickupReminder.requestID(studentID: id, leavesAt: clock(13, 30), isSample: true)
        let realID = EarlyPickupReminder.requestID(studentID: id, leavesAt: clock(13, 30), isSample: false)
        // Clearing the sample's leaves the real class's alone; clearing all takes both.
        #expect(sampleID.hasPrefix("pickup-sample-"))
        #expect(!realID.hasPrefix("pickup-sample-"))
        #expect(realID.hasPrefix("pickup-") && sampleID.hasPrefix("pickup-"))
    }

    @Test("A pickup on an unmarked copy still rings once another device marks the child present")
    func pickupOnALosingCopy() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let maya = AssistantTestSupport.student("Maya", "Stone", in: context)
        let key = try #require(maya.id?.uuidString)
        // The guide's pickup, set ahead on a record of its own...
        let planned = CDAttendanceRecord(context: context)
        planned.studentID = key
        planned.date = today
        planned.leavesAt = clock(13, 30)
        planned.modifiedAt = clock(7, 0)
        // ...and an assistant's mark that hadn't seen it, which wins the day.
        let marked = CDAttendanceRecord(context: context)
        marked.studentID = key
        marked.date = today
        marked.status = .present
        marked.modifiedAt = clock(8, 5)
        _ = context.safeSave()

        #expect(EarlyPickupReminder.pendingPickups(in: context, now: clock(9, 0)).map(\.leavesAt) == [clock(13, 30)])
        let row = try #require(AssistantTestSupport.viewModel(stack).rows.first)
        #expect(row.status == .present)
        #expect(row.leavesAt == clock(13, 30))
    }

    // MARK: - Bringing the requests up to date

    private func pickup(_ studentID: String, _ name: String, at time: Date) -> EarlyPickupReminder.Pickup {
        EarlyPickupReminder.Pickup(studentID: studentID, name: name, leavesAt: time, note: "")
    }

    @Test("With nothing changed, bringing the reminders up to date adds and removes nothing")
    func unchangedChangesNothing() {
        let pickups = [pickup("maya", "Maya S", at: clock(13, 30)), pickup("ari", "Ari C", at: clock(14, 0))]
        let wanted = EarlyPickupReminder.reminders(for: pickups, leadMinutes: 10, now: clock(9, 0), isSample: false)
        #expect(wanted.count == 2)

        let changes = EarlyPickupReminder.changes(wanted: wanted, pending: wanted)
        #expect(changes.add.isEmpty)
        #expect(changes.remove.isEmpty)
    }

    @Test("A removed pickup removes exactly its request; a moved one replaces its own")
    func removedAndMovedPickups() throws {
        let maya = pickup("maya", "Maya S", at: clock(13, 30))
        let ari = pickup("ari", "Ari C", at: clock(14, 0))
        let pending = EarlyPickupReminder.reminders(
            for: [maya, ari], leadMinutes: 10, now: clock(9, 0), isSample: false
        )
        let ariID = try #require(pending.last?.id)

        let wanted = EarlyPickupReminder.reminders(for: [maya], leadMinutes: 10, now: clock(9, 0), isSample: false)
        let removed = EarlyPickupReminder.changes(wanted: wanted, pending: pending)
        #expect(removed.remove == [ariID])
        #expect(removed.add.isEmpty)

        let moved = EarlyPickupReminder.reminders(
            for: [maya, pickup("ari", "Ari C", at: clock(14, 30))], leadMinutes: 10, now: clock(9, 0), isSample: false
        )
        let changes = EarlyPickupReminder.changes(wanted: moved, pending: pending)
        #expect(changes.remove == [ariID])
        #expect(changes.add.map(\.title) == ["Ari C leaves at \(AttendanceClock.string(clock(14, 30)))"])
    }

    @Test("Each class compares only against its own requests")
    func classesKeepTheirOwn() {
        let real = EarlyPickupReminder.requestID(studentID: "maya", leavesAt: clock(13, 30), isSample: false)
        let sample = EarlyPickupReminder.requestID(studentID: "maya", leavesAt: clock(13, 30), isSample: true)
        #expect(EarlyPickupReminder.isOwn(real, isSample: false))
        #expect(!EarlyPickupReminder.isOwn(sample, isSample: false))
        #expect(EarlyPickupReminder.isOwn(sample, isSample: true))
        #expect(!EarlyPickupReminder.isOwn(real, isSample: true))
        #expect(!EarlyPickupReminder.isOwn("arrival-day_1", isSample: false))
    }
}
