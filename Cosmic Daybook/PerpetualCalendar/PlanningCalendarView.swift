import SwiftUI
import CoreData

/// Unified planning calendar — year-at-a-glance grid that overlays:
///  • CDDayPad (the day's note: the same text as Today's Pad)
///  • PerpetualHolidays (system holidays)
///  • CDCalendarEvent (Mac calendar events synced via EventKit)
///  • CDTodoItem due dates
///  • Parsha labels (Saturdays)
///
/// Until Simplify the app's Phase 7 the notes here were their own rows
/// (`CDCalendarNote`); the Mac copies them into the day pads at launch
/// (`CalendarNotePadCopy`), and the grid reads and writes the pads. A note not
/// copied yet still shows on its day, read-only (`olderNoteLookup`).
struct PlanningCalendarView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.calendar) private var calendar

    /// Pads with something written on them; an empty one has nothing to show.
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDDayPad.day, ascending: true)],
        predicate: NSPredicate(format: "day != nil AND body != nil AND body != %@", "")
    ) private var writtenPads: FetchedResults<CDDayPad>

    /// The Calendar's own notes not marked copied into their pads yet
    /// (`CalendarNotePadCopy.notCopiedPredicate`): each is shown on its day
    /// until its text is in the day's pad (`olderNoteLookup`). Once the Mac has
    /// copied them all, this fetches nothing.
    @FetchRequest(
        sortDescriptors: [],
        predicate: CalendarNotePadCopy.notCopiedPredicate()
    ) private var waitingNotes: FetchedResults<CDCalendarNote>

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

    /// Each day's pad text. Built once per body and handed to the cells,
    /// rather than once per cell.
    private var padTexts: [CellID: String] { CalendarNoteEditor.padTexts(of: writtenPads) }

    /// Each day's Calendar notes not yet copied into its pad
    /// (`CalendarNotePadCopy.uncopiedTexts`): not marked, and not in the pad;
    /// on the iPhone and iPad, which never copy, until the Mac has. Built once
    /// per body, beside `padTexts`.
    private func olderNoteLookup(padTexts: [CellID: String]) -> [CellID: [String]] {
        CalendarNotePadCopy.uncopiedTexts(of: waitingNotes, padTexts: padTexts)
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
        let padTexts = padTexts
        let olderNotes = olderNoteLookup(padTexts: padTexts)
        CalendarGridView(
            title: "Calendar",
            columnWidth: 200,
            yearRange: yearRange,
            nonSchoolCells: nonSchoolCells,
            headerTrailing: { headerMenu },
            dayContent: { cellID, isToday, isNonSchool in
                planningDayCell(
                    cellID: cellID, isToday: isToday, isNonSchool: isNonSchool,
                    padTexts: padTexts, olderNotes: olderNotes[cellID] ?? []
                )
            }
        )
        .task { await reloadNonSchoolCells() }
        // Days off marked elsewhere (Settings, another device, Claude) shade
        // here too; the shading used to load once (2026-10-11 hunt, #41).
        .onReceive(NotificationCenter.default.publisher(for: .schoolDayDataDidChange)) { _ in
            Task { await reloadNonSchoolCells() }
        }
        // Switching sections keeps a note still being typed.
        .onDisappear { editor.commitOpenCell(in: viewContext) }
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

    /// `olderNotes` are the day's Calendar notes not yet in its pad: on the
    /// day's line after the pad's text, and, while the day's field is open,
    /// under it, outside the text being edited.
    func planningDayCell(
        cellID: CellID, isToday: Bool, isNonSchool: Bool, padTexts: [CellID: String], olderNotes: [String]
    ) -> some View {
        let holiday = showHolidays
            ? PerpetualHolidays.holiday(month: cellID.month, day: cellID.day, year: cellID.year)
            : nil
        let isEditing = editor.editingCell == cellID
        let note = showNotes
            ? ([padTexts[cellID] ?? ""] + olderNotes)
                .map(CalendarDayText.padSummary)
                .filter { !$0.isEmpty }
                .joined(separator: " \u{00B7} ")
            : ""
        let hasUserNote = !note.isEmpty

        return CalendarDayCell(
            cellID: cellID,
            isToday: isToday,
            isNonSchool: isNonSchool,
            parsha: showParsha ? CalendarDayText.parsha(for: cellID) : nil,
            displayText: hasUserNote ? note : holiday ?? "",
            isHoliday: holiday != nil && !hasUserNote,
            isEditing: isEditing,
            editsMultipleLines: editor.editsMultipleLines,
            editText: $editor.draft,
            metrics: .planning,
            onBeginEdit: { beginEdit(cellID: cellID, padTexts: padTexts) },
            onCommit: { commitEdit(cellID: cellID) },
            extra: {
                olderNoteRows(isEditing ? olderNotes : [])
                eventRows(showEvents ? (eventsLookup[cellID] ?? []) : [])
                todoRows(showTodos ? (todosLookup[cellID] ?? []) : [])
            }
        )
    }

    /// A day's Calendar notes not yet in its pad, under its open field,
    /// read-only: the Mac adds them to the pad itself, so typing them in
    /// would only put them there twice.
    @ViewBuilder
    func olderNoteRows(_ notes: [String]) -> some View {
        ForEach(notes, id: \.self) { text in
            Text("Older note: \(CalendarDayText.padSummary(text))")
                .font(.system(size: 9))
                .italic()
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(.horizontal, 8)
                .help("Written in the Calendar before it shared Today's note. "
                    + "It's added to this day's note the next time Cosmic Daybook opens on your Mac.")
        }
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

    /// Opens the day with its pad's text, even with the Notes layer hidden
    /// (the editor chooses the text; see `CalendarNoteEditor.openingText`).
    func beginEdit(cellID: CellID, padTexts: [CellID: String]) {
        editor.beginEditing(cellID, padTexts: padTexts, in: viewContext)
    }

    /// Return or focus leaving the field; a no-op once another day is open.
    func commitEdit(cellID: CellID) {
        editor.commitIfOpen(cellID, in: viewContext)
    }

    func reloadNonSchoolCells() async {
        nonSchoolCells = await NonSchoolDayCells.load(yearRange: yearRange, context: viewContext)
    }
}
