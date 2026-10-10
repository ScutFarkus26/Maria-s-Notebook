// WeekPlanSection.swift
// The merged Lessons & Work calendar: a school week of day columns sharing the
// pane's width, each carrying both presentations and work check-ins.
//
// Replaces two calendars that each drew the same days from opposite ends —
// `WeekPlanSection` showed presentations with a checkbox for work, and
// `WorkAgendaCalendarPane` showed work with a checkbox for presentations. Each
// accepted drags the other refused. This one owns its own day window, so the
// hosts just mount it and say what to open.

import Combine
import SwiftUI
import CoreData
import OSLog

struct WeekPlanSection: View {
    var focusedPresentationID: UUID?
    var onSelectPresentation: (CDLessonAssignment) -> Void
    var onOpenWork: (UUID) -> Void

    @Environment(\.calendar) var calendar
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.dependencies) var dependencies
    @Environment(SaveCoordinator.self) var saveCoordinator

    // Sorted in the fetch as well as in the column, so the persisted order
    // survives faulting rather than arriving in Core Data's row order.
    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(keyPath: \CDLessonAssignment.scheduledFor, ascending: true),
        NSSortDescriptor(keyPath: \CDLessonAssignment.createdAt, ascending: true)
    ])
    var lessonAssignments: FetchedResults<CDLessonAssignment>

    @AppStorage(UserDefaultsKeys.calendarVisibleKinds)
    var visibleKindsRaw: String = CalendarKindFilter.everything.rawValue
    @AppStorage(UserDefaultsKeys.lessonsAgendaStartDate) var startDateRaw: Double = 0
    @TestStudentVisibility var testStudents

    /// The curriculum and the roster, fetched once for the whole strip and
    /// handed to every day column. Each card used to fetch both tables itself.
    @State var cachedLessons: [CDLesson] = []
    @State var cachedStudents: [CDStudent] = []

    /// Check-ins for the whole visible range, fetched once and grouped per day.
    @State var cachedCheckIns: [CDWorkCheckIn] = []
    @State var checkInLookup = CalendarCheckInGrouper.Lookup()
    /// The day the loaded window is built around. Changing it rebuilds the
    /// window (Today, a deep link to a far-off day); scrolling does not.
    @State var startDate: Date = AppCalendar.startOfDay(Date())
    /// Every school day loaded into the strip — a few weeks either side of
    /// what is on screen, grown as the guide scrolls toward either end.
    @State var days: [Date] = []
    /// The day at the strip's leading edge, kept in step with the scroll view.
    @State var leadingDay: Date?
    /// Whether the strip is scrolling or holding a day in place, which is when
    /// it must not load more days.
    @State var stripSettle = WeekPlanDayWindow.Settle()
    @State var showClearAllConfirmation = false
    @State var selectedGroup: CalendarCheckInGroup?
    @State var prompt: WorkCheckInPlanPrompt?
    /// The strip's measured width, which the day columns share between them.
    /// Zero until the first layout, which reads as the minimum column width.
    @State var stripWidth: CGFloat = 0

    /// Days on screen at once: one school week, which is what the guide plans
    /// and what the columns divide the pane's width between. The strip scrolls
    /// through the days either side, and the arrows move it a week at a time.
    static let visibleDayCount = 5

    var visibleKinds: CalendarKindFilter {
        CalendarKindFilter.resolved(rawValue: visibleKindsRaw)
    }

    private var visibleKindsBinding: Binding<CalendarKindFilter> {
        Binding(
            get: { visibleKinds },
            set: { visibleKindsRaw = $0.rawValue }
        )
    }

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 6) {
                header
                dayStrip(proxy)
            }
            .task {
                startDate = restoredStartDate()
                refreshCardData()
                await reloadDays()
            }
            .task(id: focusedPresentationID) {
                await revealFocusedPresentation(proxy)
            }
            .onChange(of: startDate) { _, _ in
                Task { await reloadDays() }
            }
            .onChange(of: leadingDay) { _, _ in
                leadingDayChanged(proxy: proxy)
            }
            .onChange(of: visibleKindsRaw) { _, _ in
                Task { await refreshCheckIns() }
            }
            .onChange(of: lessonAssignments.count) { _, _ in
                // A presentation arriving can name a lesson or a child the
                // strip has not read yet, so the card data reloads with it.
                refreshCardData()
                Task { await refreshCheckIns() }
            }
            // A status logged from the grid, Today, the editor or over MCP
            // settles check-ins this strip is showing. Saves arrive in bursts,
            // so coalesce them — the same pattern as WorksAgendaView. Saves
            // touching nothing the check-in pills read are dropped first.
            // Only while on screen: a hidden iPad tab refreshes once on return.
            .onReceiveWhenVisible(
                NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
                    // @Sendable: runs on the saving context's queue (see onPresentationDataChange).
                    .filter { @Sendable note in
                        ManagedObjectChangeScope.saveTouches(Self.checkInEntityNames, in: note.userInfo)
                    }
                    .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            ) {
                Task { await refreshCheckIns() }
            }
        }
        .sheet(item: $selectedGroup) { group in
            WorkLogSheet(
                group: group,
                onLog: { entries in logWork(entries, on: group.sortDate) },
                onOpenWork: { workID in
                    selectedGroup = nil
                    Task {
                        // Let the sheet finish dismissing first.
                        try? await Task.sleep(for: .milliseconds(350))
                        onOpenWork(workID)
                    }
                }
            )
        }
        .sheet(item: $prompt) { active in
            PlanPromptSheetView(
                prompt: active,
                onCancel: { prompt = nil },
                onSave: { reason, note, studentInitiated in
                    scheduleCheckIn(
                        workID: active.workID,
                        date: active.date,
                        reason: reason,
                        note: note,
                        studentInitiated: studentInitiated
                    )
                    prompt = nil
                }
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        WeekPlanHeader(
            dateRangeLabel: dateRangeLabel,
            visibleKinds: visibleKinds,
            onShowEverything: { visibleKindsRaw = CalendarKindFilter.everything.rawValue },
            onToday: { jump(to: AppCalendar.startOfDay(Date())) },
            onEarlier: { movePage(by: -1) },
            onLater: { movePage(by: 1) },
            actions: { bulkActionsMenu }
        )
    }

    private var bulkActionsMenu: some View {
        Menu {
            // Here rather than on the header: the workspace above already has
            // a Presentations / Work switch, and two of them side by side read
            // as one control that did two different things.
            Picker(selection: visibleKindsBinding) {
                ForEach(CalendarKindFilter.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            } label: {
                Label("Show", systemImage: "line.3.horizontal.decrease.circle")
            }
            .pickerStyle(.menu)
            Divider()
            // The day columns each carry their own clash button; this is the
            // same gesture for a guide looking at the whole strip at once.
            Button {
                balanceVisibleDays()
            } label: {
                Label("Balance AM/PM on These Days", systemImage: "wand.and.sparkles")
            }
            Divider()
            Button {
                Task { await moveAllScheduledForward() }
            } label: {
                Label("Move All Forward 1 Day", systemImage: "arrow.right.circle")
            }
            .help("Slides every scheduled presentation and work check one school day later.")
            Button(role: .destructive) {
                showClearAllConfirmation = true
            } label: {
                Label("Clear All to Inbox", systemImage: "tray.and.arrow.up")
            }
        } label: {
            Label("Actions", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("What to show, and bulk scheduling actions")
        .confirmationDialog(
            "Clear all scheduled presentations?",
            isPresented: $showClearAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All to Inbox", role: .destructive) {
                Task { await clearAllScheduledLessonsToInbox() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Every planned presentation not yet given goes back to the Inbox.")
        }
    }

    /// The first and last of the days on screen — read off `visibleDays`, the
    /// slice of the array the columns are built from, so the two cannot disagree.
    private var dateRangeLabel: String {
        let shown = visibleDays
        guard let first = shown.first, let last = shown.last else { return "" }
        return Self.rangeLabel(first: first, last: last, calendar: calendar)
    }

    // MARK: - Day strip

    /// Five equal columns across the pane, in a strip that scrolls through the
    /// school days either side and comes to rest on a day's edge. A pane too
    /// narrow for five at the minimum width shows fewer.
    private func dayStrip(_ proxy: ScrollViewProxy) -> some View {
        let assignments = Array(lessonAssignments)
        let byDay = Self.scheduledByDay(assignments, days: days, calendar: calendar)
        let columnWidth = Self.columnWidth(forStripWidth: stripWidth, dayCount: Self.visibleDayCount)
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: Self.columnSpacing) {
                ForEach(days, id: \.self) { day in
                    WeekDayColumn(
                        day: day,
                        allLessonAssignments: assignments,
                        scheduledLessons: byDay[calendar.startOfDay(for: day)] ?? [],
                        lessons: cachedLessons,
                        students: cachedStudents,
                        visibleKinds: visibleKinds,
                        checkInGroups: checkInGroups(for: day),
                        focusedPresentationID: focusedPresentationID,
                        onClear: clearSchedule,
                        onSelect: onSelectPresentation,
                        onOpenCheckInGroup: openCheckInGroup,
                        onDropWorkCheckIns: rescheduleCheckIns,
                        onDropWork: beginPlanningWork,
                        pillActions: pillActions,
                        columnWidth: columnWidth
                    )
                    .id(day)
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, 8)
        }
        // Margins rather than padding, so a day that comes to rest at the
        // leading edge keeps the same gap the first one has.
        .contentMargins(.horizontal, Self.stripPadding, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
        .scrollPosition(id: $leadingDay, anchor: .leading)
        .onScrollPhaseChange { _, phase in
            stripScrollPhaseChanged(phase, proxy: proxy)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            stripWidth = width
        }
    }

    private func checkInGroups(for day: Date) -> [CalendarCheckInGroup] {
        let (start, end) = AppCalendar.dayRange(for: day)
        let forDay = cachedCheckIns.filter { checkIn in
            guard let date = checkIn.date else { return false }
            return date >= start && date < end
        }
        guard !forDay.isEmpty else { return [] }
        return CalendarCheckInGrouper.groups(from: forDay, lookup: checkInLookup)
    }
}

// MARK: - Per-render data

extension WeekPlanSection {
    /// What `refreshCheckIns` and the pills it feeds read: the check-ins, the
    /// work they belong to, and the lesson and child names on the pill.
    nonisolated static let checkInEntityNames: Set<String> = ["WorkCheckIn", "WorkModel", "Lesson", "Student"]

    /// Each visible day's pending presentations, in the order its column draws
    /// them: not given, scheduled on that day (`isDate(_:inSameDayAs:)` in
    /// `calendar`, i.e. the same start of day), sorted by
    /// `LessonAssignmentOrdering`. Keyed by `calendar.startOfDay(for:)`.
    ///
    /// One walk over the table per render instead of one per column per read —
    /// each column used to re-filter every assignment every time its body,
    /// header, lanes, balance button or drop delegate asked for its day.
    static func scheduledByDay(
        _ assignments: [CDLessonAssignment],
        days: [Date],
        calendar: Calendar
    ) -> [Date: [CDLessonAssignment]] {
        let wanted = Set(days.map { calendar.startOfDay(for: $0) })
        var byDay: [Date: [CDLessonAssignment]] = [:]
        for la in assignments {
            guard let scheduled = la.scheduledFor, !la.isGiven else { continue }
            let key = calendar.startOfDay(for: scheduled)
            guard wanted.contains(key) else { continue }
            byDay[key, default: []].append(la)
        }
        // Swift's sort is not stable, and every legacy row still sits at
        // midnight — the tiebreak in the ordering keeps the day from reshuffling.
        return byDay.mapValues { $0.sorted(by: LessonAssignmentOrdering.isOrderedBefore) }
    }
}

/// A pending "what is this check-in for?" question, raised by dropping a work
/// card onto a day.
struct WorkCheckInPlanPrompt: Identifiable {
    let id = UUID()
    let workID: UUID
    let date: Date
    var reason: String = "progressCheck"
    var note: String = ""
    var studentInitiated: Bool = false
}
