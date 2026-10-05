import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// The note and pickup sheets' day, the front-desk reminder's tap, and the
// bar's tap of feedback: findings of the 2026-10-04 bug hunt whose fixes
// added to what the grid's model offers.
@Suite("Assistant grid: sheets, reminders and feedback")
@MainActor
struct AssistantGridSheetsAndFeedbackTests {

    // Step 8: the sheet saved to the grid's day at the time of saving, so a
    // reminder tapped (or the morning coming round) while it was open put
    // the note on the new day.
    @Test("A note goes on the day its sheet opened on, even after the grid moved on")
    func noteKeepsItsDay() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        AssistantTestSupport.student("Ari", "Cedar", in: context)
        let monday = try AssistantTestSupport.day("2026-09-28")
        let tuesday = try AssistantTestSupport.day("2026-09-29")
        let model = AssistantTestSupport.viewModel(stack, on: monday)
        let row = try #require(model.rows.first)

        model.load(tuesday)
        model.setNote("Dentist at 2", for: row, on: monday)

        let records = context.safeFetch(CDFetchRequest(CDAttendanceRecord.self))
        #expect(records.count == 1)
        #expect(records.first?.date == monday)
        #expect(records.first?.note == "Dentist at 2")
        #expect(model.rows.first?.note == "")
    }

    @Test("A pickup time goes on the day its sheet opened on, even after the grid moved on")
    func pickupKeepsItsDay() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        AssistantTestSupport.student("Ari", "Cedar", in: context)
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: today))
        let model = AssistantTestSupport.viewModel(stack, on: today)
        let row = try #require(model.rows.first)

        model.load(tomorrow)
        let time = AttendanceRules.pickup(today.addingTimeInterval(13 * 3_600), on: today)
        model.setPickup(time, for: row, on: today)

        let records = context.safeFetch(CDFetchRequest(CDAttendanceRecord.self))
        #expect(records.count == 1)
        #expect(records.first?.date == today)
        #expect(records.first?.leavesAt == time)
        #expect(model.pickupEdits == 1)
        #expect(model.rows.first?.leavesAt == nil)
    }

    // Step 10: a tapped front-desk reminder opened the email even with
    // children unmarked, and the email lists only the marked ones.
    @Test("A tapped front-desk reminder with children unmarked asks to mark them absent first")
    func reminderTap() {
        typealias Mail = AssistantFrontDeskMail
        #expect(Mail.reminderAction(alreadySent: false, isOffered: true, unmarked: 2, canClose: true) == .askToClose)
        #expect(Mail.reminderAction(alreadySent: false, isOffered: true, unmarked: 0, canClose: true) == .openEmail)
        // A locked day, or arrival already closed: the email as it is.
        #expect(Mail.reminderAction(alreadySent: false, isOffered: true, unmarked: 2, canClose: false) == .openEmail)
        #expect(Mail.reminderAction(alreadySent: true, isOffered: true, unmarked: 2, canClose: true) == .nothing)
        #expect(Mail.reminderAction(alreadySent: false, isOffered: false, unmarked: 0, canClose: true) == .nothing)
    }

    // Step 14: the bar's feedback followed the phase, which every load works
    // out again, so another device closing arrival buzzed her phone.
    @Test("Her own Close Arrival, Reopen and Undo give feedback; another device closing arrival doesn't")
    func phaseFeedbackIsHerOwn() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let ari = AssistantTestSupport.student("Ari", "Cedar", in: context)
        AssistantTestSupport.student("Maya", "Stone", in: context)
        let model = AssistantTestSupport.viewModel(stack)
        let guide = CDAttendanceStore(context: context, role: .leadGuide)
        #expect(try guide.markUnmarkedAbsent(for: model.date, students: [ari]).count == 1)
        #expect(context.safeSave())

        model.load()
        #expect(model.phase == .late)
        #expect(model.phaseSwitches == 0)

        model.returnToArrival()
        #expect(model.phaseSwitches == 1)
        #expect(model.beginLate() == 1)
        #expect(model.phaseSwitches == 2)
        // Her Undo puts Maya back, but the guide's Close Arrival stands, so
        // the day stays Late and nothing buzzes.
        model.returnToArrival(undo: true)
        #expect(model.phase == .late)
        #expect(model.rows.first { $0.student.firstName == "Maya" }?.status == .unmarked)
        #expect(model.phaseSwitches == 2)
    }
}
