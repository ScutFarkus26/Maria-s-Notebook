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
    @Environment(\.calendar) private var calendar

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
        sortDescriptors: [NSSortDescriptor(keyPath: \CDTodoItem.dueDate, ascending: true)],
        predicate: NSPredicate(format: "dueDate != nil AND isCompleted == NO")
    ) private var openTodos: FetchedResults<CDTodoItem>

    @State private var editor = CalendarNoteEditor()
    @State private var nonSchoolCells: Set<CellID> = []
    @State private var showCalendarSync: Bool = false

    @AppStorage(UserDefaultsKeys.planningCalendarShowNotes) private var showNotes: Bool = true
    @AppStorage(UserDefaultsKeys.planningCalendarShowHolidays) private var showHolidays: Bool = true
    @AppStorage(UserDefaultsKeys.planningCalendarShowEvents) private var showEvents: Bool = true
    @AppStorage(UserDefaultsKeys.planningCalendarShowTodos) private var showTodos: Bool = true
    @AppStorage(UserDefaultsKeys.planningCalendarShowParsha) private var showParsha: Bool = true

    private static let yearRadius = 5

    private var yearRange: ClosedRange<Int> {
        let now = calendar.component(.year, from: Date())
        return (now - Self.yearRadius)...(now + Self.yearRadius)
    }

    private var notesLookup: [CellID: CDCalendarNote] { allNotes.byCell }

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

    private var todosLookup: [CellID: [CDTodoItem]] {
        var lookup: [CellID: [CDTodoItem]] = [:]
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
        .task {
            nonSchoolCells = await NonSchoolDayCells.load(yearRange: yearRange, context: viewContext)
        }
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
}

// MARK: - Day cell

private extension PlanningCalendarView {

    func planningDayCell(cellID: CellID, isToday: Bool, isNonSchool: Bool) -> some View {
        let holiday = showHolidays
            ? PerpetualHolidays.holiday(month: cellID.month, day: cellID.day, year: cellID.year)
            : nil
        let note = showNotes ? notesLookup[cellID] : nil
        let hasUserNote = note != nil && !(note?.text.isEmpty ?? true)

        return CalendarDayCell(
            cellID: cellID,
            isToday: isToday,
            isNonSchool: isNonSchool,
            parsha: showParsha ? CalendarDayText.parsha(for: cellID) : nil,
            displayText: note?.text ?? holiday ?? "",
            isHoliday: holiday != nil && !hasUserNote,
            isEditing: editor.editingCell == cellID,
            editText: $editor.draft,
            metrics: .planning,
            onBeginEdit: { beginEdit(cellID: cellID, currentText: note?.text ?? holiday ?? "") },
            onCommit: { commitEdit(cellID: cellID) },
            extra: {
                eventRows(showEvents ? (eventsLookup[cellID] ?? []) : [])
                todoRows(showTodos ? (todosLookup[cellID] ?? []) : [])
            }
        )
    }

    @ViewBuilder
    func eventRows(_ events: [CDCalendarEvent]) -> some View {
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
    }

    @ViewBuilder
    func todoRows(_ todos: [CDTodoItem]) -> some View {
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

    // MARK: - Editing

    func beginEdit(cellID: CellID, currentText: String) {
        editor.beginEditing(cellID, currentText: currentText, notes: notesLookup, in: viewContext)
    }

    func commitEdit(cellID: CellID) {
        editor.commit(cellID, notes: notesLookup, in: viewContext)
    }
}
