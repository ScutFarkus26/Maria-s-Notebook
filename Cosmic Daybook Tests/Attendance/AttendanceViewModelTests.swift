import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

// The notebook's roll: the day's rows as values, what marking allows ahead of
// the day, Close Arrival with its Undo, and Reset Day with its Undo.
@Suite("Attendance roll")
@MainActor
struct AttendanceViewModelTests {

    private let stack: CoreDataStack
    private let defaults: UserDefaults
    private let today = AppCalendar.startOfDay(Date())
    private var tomorrow: Date { Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today }

    init() throws {
        stack = try CoreDataTestHelpers.makeInMemoryStack()
        let suite = "AttendanceViewModelTests.\(UUID().uuidString)"
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

    // MARK: - Rows

    // An import that changes a record already on screen hands the roll back the
    // same object; the rows copy its values, so the change shows.
    @Test("A reload shows a record changed in place")
    func reloadSeesChangedRecord() throws {
        let chaviva = student("Chaviva")
        let store = CDAttendanceStore(context: context)
        let record = try #require(try store.ensureRecord(for: chaviva, on: today))
        #expect(store.updateStatus(record, to: .present))
        try context.save()

        let roll = model(students: [chaviva])
        #expect(status(roll, "Chaviva") == .present)

        record.status = .tardy
        roll.load(students: [chaviva], modelContext: context)
        #expect(status(roll, "Chaviva") == .tardy)
    }

    @Test("Rows follow the sort, and the tiles get the shortest names that tell children apart")
    func sortAndNames() throws {
        let students = [student("Etty", "Rosen"), student("Ari", "Adler"), student("Etty", "Gold")]
        let roll = model(students: students)
        roll.setSortKey(.lastName)
        #expect(roll.rows.map(\.shortName) == ["Ari", "Etty G", "Etty R"])
        roll.setSortKey(.firstName)
        #expect(roll.rows.map(\.name).first == "Ari Adler")
    }

    @Test("A child who started later isn't on an earlier day's roll")
    func dayRoll() throws {
        let newcomer = student("Noa")
        newcomer.dateStarted = tomorrow
        let roll = model(students: [newcomer, student("Maya")])
        #expect(roll.rows.map(\.shortName) == ["Maya"])
    }

    // MARK: - Marking

    @Test("A click marks present during arrival and a second click takes it back; the row changes each time")
    func click() throws {
        let roll = model(students: [student("Maya")])
        roll.tap(try #require(roll.rows.first), modelContext: context)
        #expect(status(roll, "Maya") == .present)
        roll.tap(try #require(roll.rows.first), modelContext: context)
        #expect(status(roll, "Maya") == .unmarked)
    }

    @Test("Ahead of the day only absences, reasons and notes are taken")
    func aheadOfTheDay() throws {
        let roll = model(on: tomorrow, students: [student("Maya")])
        let row = try #require(roll.rows.first)
        #expect(!roll.setStatus(.present, for: row, modelContext: context))
        #expect(status(roll, "Maya") == .unmarked)
        #expect(roll.statusAfterTap(for: row) == nil)

        #expect(roll.markUnmarkedPresent(modelContext: context) == nil)
        #expect(status(roll, "Maya") == .unmarked)

        roll.markAbsent(reason: .vacation, for: row, modelContext: context)
        let marked = try #require(roll.rows.first)
        #expect(marked.status == .absent && marked.absenceReason == .vacation)
        #expect(roll.completions == 0)

        roll.updateNote(for: marked, note: "Family trip", modelContext: context)
        #expect(roll.rows.first?.note == "Family trip")
    }

    @Test("An empty note on an unmarked child leaves no record behind")
    func emptyNote() throws {
        let roll = model(students: [student("Maya")])
        roll.updateNote(for: try #require(roll.rows.first), note: "  ", modelContext: context)
        #expect(context.safeFetch(CDFetchRequest(CDAttendanceRecord.self)).isEmpty)
    }

    @Test("A mark that completes the roll counts once; a load never does")
    func completion() throws {
        let roll = model(students: [student("Maya"), student("Ari")])
        roll.tap(try #require(roll.rows.first), modelContext: context)
        #expect(roll.completions == 0)
        roll.tap(try #require(roll.rows.last), modelContext: context)
        #expect(roll.completions == 1)
        roll.load(students: roll.students, modelContext: context)
        #expect(roll.completions == 1)
    }

    // MARK: - Close Arrival

    @Test("Close Arrival marks only the unmarked absent, and a tap then marks late")
    func closeArrival() throws {
        let roll = model(students: [student("Maya"), student("Ari")])
        roll.tap(try #require(roll.rows.first { $0.shortName == "Maya" }), modelContext: context)
        #expect(roll.offersCloseArrival(canMark: true))

        let undo = try #require(roll.closeArrival(modelContext: context))
        #expect(undo.records.count == 1)
        #expect(status(roll, "Ari") == .absent)
        #expect(status(roll, "Maya") == .present)
        #expect(roll.phase == .late)
        #expect(AttendanceLatePhase.isLate(on: today, defaults: defaults))

        let ari = try #require(roll.rows.first { $0.shortName == "Ari" })
        #expect(roll.statusAfterTap(for: ari) == .tardy)
        #expect(roll.closeArrival(modelContext: context) == nil)
    }

    // Loose end from the logic-break sweep (F12): only the Assistant's grid
    // retired Siri's Undo, so after the notebook's Close Arrival "Undo that"
    // put back a voice mark made before it.
    @Test("Close Arrival retires Siri's Undo for that day, not another day's")
    func closeArrivalRetiresSiriUndo() throws {
        let roll = model(students: [student("Maya")])
        SiriAttendanceChange(day: today, marks: [], summary: "Maya Stone present", closedArrival: false)
            .remember(defaults: defaults)
        #expect(roll.closeArrival(modelContext: context) != nil)
        #expect(SiriAttendanceChange.last(defaults: defaults) == nil)

        SiriAttendanceChange(day: today, marks: [], summary: "Ari Stone absent", closedArrival: false)
            .remember(defaults: defaults)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        let earlier = model(on: yesterday, students: [student("Lea")])
        #expect(earlier.closeArrival(modelContext: context) != nil)
        #expect(SiriAttendanceChange.last(defaults: defaults)?.summary == "Ari Stone absent")
    }

    @Test("Undoing Close Arrival skips a child marked late since")
    func undoCloseArrival() throws {
        let roll = model(students: [student("Maya"), student("Ari")])
        let undo = try #require(roll.closeArrival(modelContext: context))
        // The screen saves after closing: the Undo must still find records it created.
        try context.save()
        roll.tap(try #require(roll.rows.first { $0.shortName == "Ari" }), modelContext: context)
        #expect(status(roll, "Ari") == .tardy)

        #expect(roll.undoCloseArrival(undo, modelContext: context) == 1)
        #expect(status(roll, "Maya") == .unmarked)
        #expect(status(roll, "Ari") == .tardy)
        #expect(roll.phase == .arrival)
        #expect(!AttendanceLatePhase.isLate(on: today, defaults: defaults))
    }

    @Test("Close Arrival isn't offered ahead of the day or on a locked day")
    func closeArrivalRefused() throws {
        let maya = student("Maya")
        let ahead = model(on: tomorrow, students: [maya])
        #expect(!ahead.offersCloseArrival(canMark: true))
        #expect(ahead.closeArrival(modelContext: context) == nil)

        #expect(AttendanceDayLocks.setLocked(true, for: today, role: .leadGuide, lockedByID: nil, in: context))
        let locked = model(students: [maya])
        #expect(locked.closeArrival(modelContext: context) == nil)
        #expect(status(locked, "Maya") == .unmarked)
    }

    // MARK: - Welcome back and the day's number

    private func mark(_ student: CDStudent, _ status: AttendanceStatus, on day: String) throws {
        let store = CDAttendanceStore(context: context)
        let record = try #require(try store.ensureRecord(for: student, on: try CoreDataTestHelpers.day(day)))
        #expect(store.updateStatus(record, to: status))
    }

    @Test("A child absent the last three school days is welcomed back when marked in")
    func welcomeBack() throws {
        let maya = student("Maya")
        let ari = student("Ari")
        for day in ["2026-09-09", "2026-09-10", "2026-09-11"] { try mark(maya, .absent, on: day) }
        try mark(ari, .absent, on: "2026-09-11")
        let roll = model(on: try CoreDataTestHelpers.day("2026-09-14"), students: [maya, ari])
        let mayaRow = try #require(roll.rows.first { $0.shortName == "Maya" })
        #expect(mayaRow.daysAway == 3)
        #expect(roll.rows.first { $0.shortName == "Ari" }?.daysAway == nil)

        roll.tap(mayaRow, modelContext: context)
        #expect(roll.welcome?.name == "Maya")
    }

    @Test("Marking a returning child absent again welcomes no one")
    func noWelcomeForAbsence() throws {
        let maya = student("Maya")
        for day in ["2026-09-09", "2026-09-10", "2026-09-11"] { try mark(maya, .absent, on: day) }
        let roll = model(on: try CoreDataTestHelpers.day("2026-09-14"), students: [maya])
        roll.markAbsent(reason: .sick, for: try #require(roll.rows.first), modelContext: context)
        #expect(roll.welcome == nil)
    }

    @Test("The day's number counts school days from the year's first child marked here")
    func dayNumber() throws {
        let maya = student("Maya")
        try mark(maya, .present, on: "2026-09-01")
        let roll = model(on: try CoreDataTestHelpers.day("2026-09-14"), students: [maya])
        // Sep 1–4, 7–11 and 14: ten school days, with no days off entered.
        #expect(roll.dayNumber == 10)
        #expect(roll.dayLabel == "Day 10")

        roll.load(for: try CoreDataTestHelpers.day("2026-09-01"), students: [maya], modelContext: context)
        #expect(roll.milestone == .firstDay)
        #expect(roll.dayLabel == "First Day")
    }

    @Test("No count before anyone has been marked here this year")
    func noDayNumberYet() throws {
        let roll = model(on: try CoreDataTestHelpers.day("2026-09-14"), students: [student("Maya")])
        #expect(roll.dayNumber == nil)
        #expect(roll.dayLabel == nil)
    }

    // MARK: - Reset

    @Test("Undoing Reset Day puts back marks, reasons, notes and times")
    func undoReset() throws {
        let roll = model(students: [student("Maya"), student("Ari")])
        let maya = try #require(roll.rows.first { $0.shortName == "Maya" })
        roll.setStatus(.present, for: maya, modelContext: context)
        roll.updateNote(for: maya, note: "Brought the snack", modelContext: context)
        let ari = try #require(roll.rows.first { $0.shortName == "Ari" })
        roll.markAbsent(reason: .sick, for: ari, modelContext: context)
        let arrived = roll.rows.first { $0.shortName == "Maya" }?.markedAt
        _ = roll.closeArrival(modelContext: context)

        let undo = try #require(roll.resetDay(modelContext: context))
        #expect(roll.rows.allSatisfy { $0.status == .unmarked && $0.note.isEmpty })
        // The screen saves after resetting; the marks were never saved before it.
        try context.save()
        #expect(roll.phase == .arrival)

        #expect(roll.undoReset(undo, modelContext: context) == 2)
        let restored = try #require(roll.rows.first { $0.shortName == "Maya" })
        #expect(restored.status == .present)
        #expect(restored.note == "Brought the snack")
        #expect(restored.markedAt == arrived)
        #expect(roll.rows.first { $0.shortName == "Ari" }?.absenceReason == .sick)
        #expect(roll.phase == .late)
    }

    @Test("Undoing Reset Day leaves a child marked again since")
    func undoResetSkipsRemarked() throws {
        let roll = model(students: [student("Maya")])
        roll.setStatus(.absent, for: try #require(roll.rows.first), modelContext: context)
        let undo = try #require(roll.resetDay(modelContext: context))
        roll.setStatus(.present, for: try #require(roll.rows.first), modelContext: context)

        #expect(roll.undoReset(undo, modelContext: context) == 0)
        #expect(status(roll, "Maya") == .present)
    }

    @Test("Resetting a day with nothing on it offers no Undo")
    func resetNothing() throws {
        let roll = model(students: [student("Maya")])
        #expect(roll.resetDay(modelContext: context) == nil)
    }
}
