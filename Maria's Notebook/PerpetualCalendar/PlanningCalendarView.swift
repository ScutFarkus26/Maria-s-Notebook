import SwiftUI
import CoreData

/// Unified planning calendar — year-at-a-glance grid that overlays:
///  • CDCalendarNote (user notes)
///  • PerpetualHolidays (system holidays)
///  • CDCalendarEvent (Mac calendar events synced via EventKit)
///  • CDTodoItem due dates
///  • Parsha labels (Saturdays)
struct PlanningCalendarView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \CDCalendarNote.year, ascending: true),
            NSSortDescriptor(keyPath: \CDCalendarNote.month, ascending: true),
            NSSortDescriptor(keyPath: \CDCalendarNote.day, ascending: true)
        ]
    ) private var allNotes: FetchedResults<CDCalendarNote>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDCalendarEvent.startDate, ascending: true)]
    ) private var allEvents: FetchedResults<CDCalendarEvent>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDTodoItemEntity.dueDate, ascending: true)],
        predicate: NSPredicate(format: "dueDate != nil AND isCompleted == NO")
    ) private var openTodos: FetchedResults<CDTodoItemEntity>

    @State private var editingCell: CellID?
    @State private var editText: String = ""
    @State private var nonSchoolCells: Set<CellID> = []
    @State private var showCalendarSync: Bool = false

    @AppStorage("PlanningCalendar.showNotes") private var showNotes: Bool = true
    @AppStorage("PlanningCalendar.showHolidays") private var showHolidays: Bool = true
    @AppStorage("PlanningCalendar.showEvents") private var showEvents: Bool = true
    @AppStorage("PlanningCalendar.showTodos") private var showTodos: Bool = true
    @AppStorage("PlanningCalendar.showParsha") private var showParsha: Bool = true

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

    private var eventsLookup: [CellID: [CDCalendarEvent]] {
        var lookup: [CellID: [CDCalendarEvent]] = [:]
        let cal = AppCalendar.shared
        for event in allEvents {
            guard let start = event.startDate else { continue }
            let comps = cal.dateComponents([.year, .month, .day], from: start)
            guard let y = comps.year, let m = comps.month, let d = comps.day else { continue }
            let cellID = CellID(year: y, month: m, day: d)
            lookup[cellID, default: []].append(event)
        }
        return lookup
    }

    private var todosLookup: [CellID: [CDTodoItemEntity]] {
        var lookup: [CellID: [CDTodoItemEntity]] = [:]
        let cal = AppCalendar.shared
        for todo in openTodos {
            guard let due = todo.dueDate else { continue }
            let comps = cal.dateComponents([.year, .month, .day], from: due)
            guard let y = comps.year, let m = comps.month, let d = comps.day else { continue }
            let cellID = CellID(year: y, month: m, day: d)
            lookup[cellID, default: []].append(todo)
        }
        return lookup
    }

    var body: some View {
        CalendarGridView(
            title: "Calendar",
            columnWidth: 180,
            yearRange: yearRange,
            nonSchoolCells: nonSchoolCells,
            headerTrailing: { headerMenu },
            dayContent: { cellID, isToday, isNonSchool in
                planningDayCell(cellID: cellID, isToday: isToday, isNonSchool: isNonSchool)
            }
        )
        .task { await loadNonSchoolDays() }
        .sheet(isPresented: $showCalendarSync) {
            CalendarSyncSettingsView()
        }
    }

    // MARK: - Header menu

    @ViewBuilder
    private var headerMenu: some View {
        Menu {
            Section("Show layers") {
                Toggle("Notes", isOn: $showNotes)
                Toggle("Holidays", isOn: $showHolidays)
                Toggle("Mac Events", isOn: $showEvents)
                Toggle("Todo Deadlines", isOn: $showTodos)
                Toggle("Parsha Labels", isOn: $showParsha)
            }
            Divider()
            Button {
                showCalendarSync = true
            } label: {
                Label("Mac Calendar Sync…", systemImage: "calendar.badge.plus")
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.title3)
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Day cell

    @ViewBuilder
    private func planningDayCell(cellID: CellID, isToday: Bool, isNonSchool: Bool) -> some View {
        let holiday = showHolidays ? PerpetualHolidays.holiday(month: cellID.month, day: cellID.day, year: cellID.year) : nil
        let note = showNotes ? notesLookup[cellID] : nil
        let displayText = note?.text ?? holiday ?? ""
        let isEditing = editingCell == cellID
        let hasUserNote = note != nil && !(note?.text.isEmpty ?? true)
        let isHoliday = holiday != nil && !hasUserNote
        let parsha = showParsha ? parshaName(for: cellID) : nil
        let events = showEvents ? (eventsLookup[cellID] ?? []) : []
        let todos = showTodos ? (todosLookup[cellID] ?? []) : []

        VStack(alignment: .leading, spacing: 1) {
            if let parsha {
                Text(parsha)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.red.opacity(UIConstants.OpacityConstants.half))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.top, 1)
            }

            HStack(spacing: 4) {
                Text("\(cellID.day)")
                    .font(.system(.caption, design: .rounded).monospacedDigit())
                    .foregroundStyle(isToday ? Color.white : (isNonSchool ? Color.red.opacity(UIConstants.OpacityConstants.half) : Color.secondary))
                    .frame(width: 22, height: 22)
                    .background { if isToday { Circle().fill(Color.accentColor) } }

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
            .padding(.horizontal, 8)

            if !events.isEmpty {
                ForEach(events.prefix(2), id: \.objectID) { event in
                    Text(event.title.isEmpty ? "Event" : event.title)
                        .font(.system(size: 9, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                }
                if events.count > 2 {
                    Text("+\(events.count - 2) more")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                }
            }

            if !todos.isEmpty {
                ForEach(todos.prefix(2), id: \.objectID) { todo in
                    HStack(spacing: 3) {
                        Text("•")
                            .font(.system(size: 10))
                        Text(todo.title.isEmpty ? "Untitled" : todo.title)
                            .font(.system(size: 9))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                }
                if todos.count > 2 {
                    Text("+\(todos.count - 2) todos")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                }
            }
        }
        .padding(.vertical, 1)
    }

    // MARK: - Helpers (mirror PerpetualCalendarView)

    private func textStyle(isHoliday: Bool, isNoSchool: Bool) -> some ShapeStyle {
        if isNoSchool { return AnyShapeStyle(.red.opacity(UIConstants.OpacityConstants.half)) }
        if isHoliday { return AnyShapeStyle(.secondary) }
        return AnyShapeStyle(.primary)
    }

    private func parshaName(for cellID: CellID) -> String? {
        let cal = AppCalendar.shared
        var comps = DateComponents()
        comps.year = cellID.year
        comps.month = cellID.month
        comps.day = cellID.day
        guard let date = cal.date(from: comps),
              cal.component(.weekday, from: date) == 7,
              let key = HebrewParshaService.currentParshaKey(on: date) else {
            return nil
        }
        return HebrewParshaService.displayName(forKey: key)
    }

    private func beginEdit(cellID: CellID, currentText: String) {
        if let previous = editingCell, previous != cellID {
            commitEdit(cellID: previous)
        }
        editText = currentText
        editingCell = cellID
    }

    private func commitEdit(cellID: CellID) {
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

    private func loadNonSchoolDays() async {
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
