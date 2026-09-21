import SwiftUI
import CoreData

// MARK: - Perpetual Calendar View

struct PerpetualCalendarView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.calendar) private var calendar
    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(keyPath: \CDCalendarNote.year, ascending: true),
        NSSortDescriptor(keyPath: \CDCalendarNote.month, ascending: true),
        NSSortDescriptor(keyPath: \CDCalendarNote.day, ascending: true)
    ]) private var allNotes: FetchedResults<CDCalendarNote>

    @State private var editor = CalendarNoteEditor()
    @State private var nonSchoolCells: Set<CellID> = []

    private static let yearRadius = 5

    private var yearRange: ClosedRange<Int> {
        let now = calendar.component(.year, from: Date())
        return (now - Self.yearRadius)...(now + Self.yearRadius)
    }

    private var notesLookup: [CellID: CDCalendarNote] { allNotes.byCell }

    var body: some View {
        CalendarGridView(
            title: "Calendar",
            columnWidth: 164,
            yearRange: yearRange,
            nonSchoolCells: nonSchoolCells
        ) { cellID, isToday, isNonSchool in
            noteDayRow(cellID: cellID, isToday: isToday, isNonSchool: isNonSchool)
        }
        .task {
            nonSchoolCells = await NonSchoolDayCells.load(yearRange: yearRange, context: viewContext)
        }
    }
}

// MARK: - Day Row & Editing

private extension PerpetualCalendarView {

    func noteDayRow(cellID: CellID, isToday: Bool, isNonSchool: Bool) -> some View {
        let holiday = PerpetualHolidays.holiday(month: cellID.month, day: cellID.day, year: cellID.year)
        let note = notesLookup[cellID]
        let hasUserNote = note != nil && !(note?.text.isEmpty ?? true)

        return CalendarDayCell(
            cellID: cellID,
            isToday: isToday,
            isNonSchool: isNonSchool,
            parsha: CalendarDayText.parsha(for: cellID),
            displayText: note?.text ?? holiday ?? "",
            isHoliday: holiday != nil && !hasUserNote,
            isEditing: editor.editingCell == cellID,
            editText: $editor.draft,
            metrics: .perpetual,
            onBeginEdit: { beginEdit(cellID: cellID, currentText: note?.text ?? holiday ?? "") },
            onCommit: { commitEdit(cellID: cellID) }
        )
    }

    func beginEdit(cellID: CellID, currentText: String) {
        editor.beginEditing(cellID, currentText: currentText, notes: notesLookup, in: viewContext)
    }

    func commitEdit(cellID: CellID) {
        editor.commit(cellID, notes: notesLookup, in: viewContext)
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct PerpetualCalendarViewPreview: View {
    var body: some View {
        PerpetualCalendarView()
            .previewEnvironment()
    }
}

#Preview {
    PerpetualCalendarViewPreview()
}
