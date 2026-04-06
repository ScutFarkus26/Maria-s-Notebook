import SwiftUI
import CoreData

// MARK: - Perpetual Calendar View

struct PerpetualCalendarView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDCalendarNote.year, ascending: true), NSSortDescriptor(keyPath: \CDCalendarNote.month, ascending: true), NSSortDescriptor(keyPath: \CDCalendarNote.day, ascending: true)]) private var allNotes: FetchedResults<CDCalendarNote>

    @State private var editingCell: CellID?
    @State private var editText: String = ""
    @State private var nonSchoolCells: Set<CellID> = []

    private static let yearRadius = 5

    private var yearRange: ClosedRange<Int> {
        let now = Calendar.current.component(.year, from: Date())
        return (now - Self.yearRadius)...(now + Self.yearRadius)
    }

    private var notesLookup: [CellID: CDCalendarNote] {
        var lookup: [CellID: CDCalendarNote] = [:]
        for note in allNotes {
            lookup[CellID(year: Int(note.year), month: Int(note.month), day: Int(note.day))] = note
        }
        return lookup
    }

    var body: some View {
        CalendarGridView(
            title: "Calendar",
            columnWidth: 164,
            yearRange: yearRange,
            nonSchoolCells: nonSchoolCells
        ) { cellID, isToday, isNonSchool in
            noteDayRow(cellID: cellID, isToday: isToday, isNonSchool: isNonSchool)
        }
        .task { await loadNonSchoolDays() }
    }
}

// MARK: - Non-School Day Loading

private extension PerpetualCalendarView {

    func loadNonSchoolDays() async {
        let cal = AppCalendar.shared
        let range = yearRange
        var startComps = DateComponents()
        startComps.year = range.lowerBound
        startComps.month = 1
        startComps.day = 1
        let years = range.upperBound - range.lowerBound + 1
        guard let start = cal.date(from: startComps),
              let end = cal.date(byAdding: .year, value: years, to: start) else { return }

        let dates = await SchoolCalendar.nonSchoolDays(in: start..<end, using: viewContext)
        var cells = Set<CellID>()
        for date in dates {
            cells.insert(CellID(
                year: cal.component(.year, from: date),
                month: cal.component(.month, from: date),
                day: cal.component(.day, from: date)
            ))
        }
        await MainActor.run {
            nonSchoolCells = cells
        }
    }
}

// MARK: - Day Row & Editing

private extension PerpetualCalendarView {

    func noteDayRow(cellID: CellID, isToday: Bool, isNonSchool: Bool) -> some View {
        let holiday = PerpetualHolidays.holiday(month: cellID.month, day: cellID.day, year: cellID.year)
        let note = notesLookup[cellID]
        let displayText = note?.text ?? holiday ?? ""
        let isEditing = editingCell == cellID
        let hasUserNote = note != nil && !(note?.text.isEmpty ?? true)
        let isHoliday = holiday != nil && !hasUserNote

        return HStack(spacing: 4) {
            Text("\(cellID.day)")
                .font(.system(.caption, design: .rounded).monospacedDigit())
                .foregroundStyle(isToday ? Color.white : (isNonSchool ? Color.red.opacity(UIConstants.OpacityConstants.half) : Color.secondary))
                .frame(width: 22, height: 22)
                .background {
                    if isToday {
                        Circle().fill(Color.accentColor)
                    }
                }

            if isEditing {
                TextField("", text: $editText)
                    .font(.system(.caption, design: .rounded))
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onSubmit { commitEdit(cellID: cellID) }
            } else {
                Text(displayText)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(textStyle(isHoliday: isHoliday, isNoSchool: isNonSchool))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        beginEdit(cellID: cellID, currentText: note?.text ?? holiday ?? "")
                    }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 1)
    }

    func textStyle(isHoliday: Bool, isNoSchool: Bool) -> some ShapeStyle {
        if isNoSchool { return AnyShapeStyle(.red.opacity(UIConstants.OpacityConstants.half)) }
        if isHoliday { return AnyShapeStyle(.secondary) }
        return AnyShapeStyle(.primary)
    }

    func beginEdit(cellID: CellID, currentText: String) {
        if let previous = editingCell, previous != cellID {
            commitEdit(cellID: previous)
        }
        editText = currentText
        editingCell = cellID
    }

    func commitEdit(cellID: CellID) {
        let trimmed = editText.trimmed()
        let holiday = PerpetualHolidays.holiday(month: cellID.month, day: cellID.day, year: cellID.year)

        if let existing = notesLookup[cellID] {
            if trimmed.isEmpty || trimmed == holiday {
                viewContext.delete(existing)
            } else {
                existing.text = trimmed
                existing.modifiedAt = Date()
            }
        } else if !trimmed.isEmpty && trimmed != holiday {
            let newNote = CDCalendarNote(context: viewContext)
            newNote.year = Int64(cellID.year)
            newNote.month = Int64(cellID.month)
            newNote.day = Int64(cellID.day)
            newNote.text = trimmed
        }

        viewContext.safeSave()
        editingCell = nil
        editText = ""
    }
}

#Preview {
    PerpetualCalendarView()
        .previewEnvironment()
}
