import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

// The roll's undoable changes: Mark N Present with its Undo, and one child's
// mark with ⌘Z (and the redo that undoing it leaves).
@Suite("Attendance roll undo")
@MainActor
struct AttendanceUndoTests {

    private let stack: CoreDataStack
    private let defaults: UserDefaults
    private let today = AppCalendar.startOfDay(Date())

    init() throws {
        stack = try CoreDataTestHelpers.makeInMemoryStack()
        let suite = "AttendanceUndoTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    private var context: NSManagedObjectContext { stack.viewContext }

    @discardableResult
    private func student(_ first: String, _ last: String = "Stone") -> CDStudent {
        let student = CDStudent(context: context)
        student.id = UUID()
        student.firstName = first
        student.lastName = last
        student.dateStarted = Calendar.current.date(byAdding: .year, value: -1, to: today)
        return student
    }

    private func model(on day: Date? = nil, students: [CDStudent]) -> AttendanceViewModel {
        let model = AttendanceViewModel(selectedDate: day ?? today, defaults: defaults)
        model.load(students: students, modelContext: context)
        return model
    }

    private func status(_ model: AttendanceViewModel, _ first: String) -> AttendanceStatus? {
        model.rows.first { $0.student.firstName == first }?.status
    }

    @Test("Mark N Present marks only the unmarked, and its Undo takes back only those")
    func markRestPresent() throws {
        let roll = model(students: [student("Maya"), student("Ari"), student("Lea")])
        let ari = try #require(roll.rows.first { $0.shortName == "Ari" })
        #expect(roll.setStatus(.tardy, for: ari, modelContext: context))
        let undo = try #require(roll.markUnmarkedPresent(modelContext: context))
        try context.save()
        #expect(undo.records.count == 2)
        #expect(status(roll, "Maya") == .present && status(roll, "Lea") == .present)
        #expect(status(roll, "Ari") == .tardy)
        #expect(roll.markUnmarkedPresent(modelContext: context) == nil)

        // Lea is marked absent after; the Undo leaves her be.
        let lea = try #require(roll.rows.first { $0.shortName == "Lea" })
        #expect(roll.setStatus(.absent, for: lea, modelContext: context))
        #expect(roll.undoBulkMark(undo, modelContext: context) == 1)
        #expect(status(roll, "Maya") == .unmarked)
        #expect(status(roll, "Lea") == .absent)
        #expect(status(roll, "Ari") == .tardy)
    }

    // Bug hunt 2026-10-03, A5: the Undo matched the status alone, so it
    // unmarked a child changed since without changing her status.
    @Test("Mark N Present's Undo leaves a child who went out and came back since")
    func markRestPresentUndoKeepsTrip() throws {
        let roll = model(students: [student("Maya"), student("Ari")])
        let undo = try #require(roll.markUnmarkedPresent(modelContext: context))
        try context.save()
        let maya = try #require(roll.rows.first { $0.shortName == "Maya" })
        #expect(roll.setStatus(.leftEarly, for: maya, modelContext: context))
        roll.markBack(try #require(roll.rows.first { $0.shortName == "Maya" }), modelContext: context)
        #expect(status(roll, "Maya") == .present)

        #expect(roll.undoBulkMark(undo, modelContext: context) == 1)
        #expect(status(roll, "Maya") == .present)
        #expect(roll.rows.first { $0.shortName == "Maya" }?.leftAt != nil)
        #expect(status(roll, "Ari") == .unmarked)
    }

    @Test("Close Arrival's Undo leaves a child given a reason since")
    func closeArrivalUndoKeepsReason() throws {
        let roll = model(students: [student("Maya"), student("Ari")])
        let undo = try #require(roll.closeArrival(modelContext: context))
        try context.save()
        let ari = try #require(roll.rows.first { $0.shortName == "Ari" })
        roll.markAbsent(reason: .sick, for: ari, modelContext: context)

        #expect(roll.undoCloseArrival(undo, modelContext: context) == 1)
        #expect(status(roll, "Maya") == .unmarked)
        #expect(status(roll, "Ari") == .absent)
        #expect(roll.rows.first { $0.shortName == "Ari" }?.absenceReason == .sick)
    }

    @Test("Undoing a mark puts the child back as they were, and the undo of the undo redoes it")
    func undoMark() throws {
        let roll = model(students: [student("Maya")])
        let first = try #require(roll.rows.first)
        let undo = try #require(roll.recordingUndo(for: first, modelContext: context) {
            roll.tap($0, modelContext: context)
        })
        try context.save()
        #expect(status(roll, "Maya") == .present)

        let redo = try #require(roll.undoMark(undo, modelContext: context))
        #expect(status(roll, "Maya") == .unmarked)
        #expect(roll.undoMark(redo, modelContext: context) != nil)
        #expect(status(roll, "Maya") == .present)
    }

    @Test("A mark changed since isn't undone")
    func undoMarkSkipsChanged() throws {
        let roll = model(students: [student("Maya")])
        let first = try #require(roll.rows.first)
        let undo = try #require(roll.recordingUndo(for: first, modelContext: context) {
            roll.tap($0, modelContext: context)
        })
        let maya = try #require(roll.rows.first)
        #expect(roll.setStatus(.absent, for: maya, modelContext: context))
        #expect(roll.undoMark(undo, modelContext: context) == nil)
        #expect(status(roll, "Maya") == .absent)
    }
}
