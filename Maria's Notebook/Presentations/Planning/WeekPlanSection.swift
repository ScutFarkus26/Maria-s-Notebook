// WeekPlanSection.swift
// The merged Lessons & Work calendar: a horizontally scrolling strip of school
// days carrying both presentations and work check-ins.
//
// Replaces two calendars that each drew the same days from opposite ends —
// `WeekPlanSection` showed presentations with a checkbox for work, and
// `WorkAgendaCalendarPane` showed work with a checkbox for presentations. Each
// accepted drags the other refused. This one owns its own day window, so the
// hosts just mount it and say what to open.

import SwiftUI
import CoreData
import OSLog

struct WeekPlanSection: View {
    static let logger = Logger.presentations

    var focusedPresentationID: UUID?
    var onSelectPresentation: (CDLessonAssignment) -> Void
    var onOpenWork: (UUID) -> Void

    @Environment(\.calendar) var calendar
    @Environment(\.managedObjectContext) var viewContext
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

    /// Check-ins for the whole visible range, fetched once and grouped per day.
    @State var cachedCheckIns: [CDWorkCheckIn] = []
    @State var checkInLookup = CalendarCheckInGrouper.Lookup()
    @State var startDate: Date = AppCalendar.startOfDay(Date())
    @State var days: [Date] = []
    @State var showClearAllConfirmation = false
    @State var selectedGroup: CalendarCheckInGroup?
    @State var prompt: WorkCheckInPlanPrompt?

    static let visibleDayCount = 10

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
                dayStrip
            }
            .task {
                startDate = restoredStartDate()
                await reloadDays()
                scrollToFirstDay(proxy)
            }
            .task(id: focusedPresentationID) {
                await revealFocusedPresentation(proxy)
            }
            .onChange(of: startDate) { _, _ in
                Task { await reloadDays(); scrollToFirstDay(proxy) }
            }
            .onChange(of: visibleKindsRaw) { _, _ in
                Task { await refreshCheckIns() }
            }
            .onChange(of: lessonAssignments.count) { _, _ in
                Task { await refreshCheckIns() }
            }
        }
        .sheet(item: $selectedGroup) { group in
            GroupedCheckInDetailSheet(sequence: group) { workID in
                selectedGroup = nil
                Task { @MainActor in
                    // Let the sequence sheet finish dismissing first.
                    try? await Task.sleep(for: .milliseconds(350))
                    onOpenWork(workID)
                }
            }
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
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Button("Today") { startDate = AppCalendar.startOfDay(Date()) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button {
                    moveStart(bySchoolDays: -UIConstants.planningNavigationStepSchoolDays)
                } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                    .help("Earlier days")

                Text(dateRangeLabel)
                    .font(.subheadline.weight(.medium))
                    .frame(minWidth: 180)
                    .multilineTextAlignment(.center)

                Button {
                    moveStart(bySchoolDays: UIConstants.planningNavigationStepSchoolDays)
                } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain)
                    .help("Later days")

                Spacer()

                Picker("Show", selection: visibleKindsBinding) {
                    ForEach(CalendarKindFilter.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()

                bulkActionsMenu
            }
            .padding(.horizontal, 12)

            HStack(spacing: 14) {
                Spacer()
                legend
            }
            .padding(.horizontal, 12)
        }
    }

    private var bulkActionsMenu: some View {
        Menu {
            Button {
                Task { await moveAllScheduledLessonsForward() }
            } label: {
                Label("Move All Forward 1 Day", systemImage: "arrow.right.circle")
            }
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
        .help("Bulk scheduling actions")
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
            Text("This will move every scheduled, ungiven presentation back to On Deck.")
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendSwatch(color: .red, label: "Absent")
            legendSwatch(color: AppColors.attention, label: "Scheduled more than once")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendSwatch(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Capsule()
                .stroke(color, lineWidth: 1)
                .frame(width: 18, height: 11)
            Text(label)
        }
    }

    /// Human-readable range covering the currently visible school days.
    private var dateRangeLabel: String {
        guard let first = days.first, let last = days.last else { return "" }
        let format = Date.FormatStyle().month(.abbreviated).day().year()
        let shortFormat = Date.FormatStyle().month(.abbreviated).day()
        if calendar.isDate(first, inSameDayAs: last) {
            return first.formatted(format)
        }
        let sameYear = calendar.component(.year, from: first) == calendar.component(.year, from: last)
        let startText = sameYear ? first.formatted(shortFormat) : first.formatted(format)
        return "\(startText) – \(last.formatted(format))"
    }

    // MARK: - Day strip

    private var dayStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(days, id: \.self) { day in
                    WeekDayColumn(
                        day: day,
                        allLessonAssignments: Array(lessonAssignments),
                        visibleKinds: visibleKinds,
                        checkInGroups: checkInGroups(for: day),
                        focusedPresentationID: focusedPresentationID,
                        onClear: clearSchedule,
                        onSelect: onSelectPresentation,
                        onOpenCheckInGroup: openCheckInGroup,
                        onDropWorkCheckIn: rescheduleCheckIn,
                        onDropWork: beginPlanningWork
                    )
                    .id(day)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
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
