// TodayViewCheckInFollowUpRows.swift
// A due work check-in as a row in the Today todo list: done or rescheduled
// from the row, and marked when a child on it has left the classroom.
//
// The day picker's state lives in the row, not in TodayView, so the screen
// gains no @State for this — each row owns its own "Reschedule…" popover.

import CoreData
import OSLog
import SwiftUI

// MARK: - Row

struct WorkCheckInFollowUpRow: View {
    let item: WorkCheckInFollowUp
    /// Whose row it is, owner first — the owner alone on a linked copy;
    /// `departed` styles the name.
    let names: [(name: String, departed: Bool)]
    /// Classmates named on a linked copy who have copies of their own.
    var companions: [String] = []
    /// Work title or lesson name, plus the check-in's purpose when it has one.
    let detail: String
    /// The work's open linked todos; the Todos list leaves them out for this row.
    var linkedTodos: TodayLinkedTodos.WorkTodos?
    var onComplete: () -> Void
    var onOpen: () -> Void
    var onReschedule: (Date) -> Void
    /// Logs a status on the work — the check-in is marked done with it.
    var onLog: (WorkStatus) -> Void = { _ in }

    @State private var isPickingDay = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onComplete) {
                checkboxView
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark checked in")

            Button(action: onOpen) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        titleLine
                            .font(AppTheme.ScaledFont.callout)
                            .lineLimit(2)
                        HStack(spacing: 8) {
                            dateChip
                            if item.hasDepartedParticipant {
                                departedMark
                            }
                            if let linkedTodos {
                                TodayLinkedTodosLabel(todos: linkedTodos)
                            }
                            Text(detail)
                                .font(AppTheme.ScaledFont.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
            }
            .buttonStyle(.subtleRow)
        }
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint("Opens the work")
        .swipeActions(edge: .leading) {
            Button(action: onComplete) {
                Label("Complete", systemImage: "checkmark")
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing) {
            Button { isPickingDay = true } label: {
                Label("Reschedule", systemImage: SFSymbol.Time.calendar)
            }
            .tint(.blue)
        }
        .contextMenu {
            Button(action: onOpen) {
                Label("Open Work", systemImage: "doc.text.magnifyingglass")
            }
            Button(action: onComplete) {
                Label("Complete", systemImage: "checkmark.circle")
            }
            Button { isPickingDay = true } label: {
                Label("Reschedule…", systemImage: SFSymbol.Time.calendar)
            }
            Divider()
            WorkLogStatusMenu(targets: [item.work]) { _, status in onLog(status) }
        }
        .modifier(DayPickerPresentation(isPresented: $isPickingDay, onPick: onReschedule))
    }

    // MARK: Pieces

    private var checkboxView: some View {
        Circle()
            .strokeBorder(Color.orange.opacity(UIConstants.OpacityConstants.half), lineWidth: 1.5)
            .overlay {
                Image(systemName: SFSymbol.Time.clock)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
    }

    /// "Check in with Ora K, Naomi L" — departed names in tertiary — and on
    /// a linked copy "Check in with Maya S · with Eli R, Ana T".
    private var titleLine: Text {
        let named = names.enumerated().reduce(Text("Check in with ")) { text, pair in
            let (index, entry) = pair
            let name = entry.departed ? Text(entry.name).foregroundStyle(.tertiary) : Text(entry.name)
            return index > 0 ? Text("\(text), \(name)") : Text("\(text)\(name)")
        }
        guard !companions.isEmpty else { return named }
        let company = Text(" · with \(companions.joined(separator: ", "))").foregroundStyle(.secondary)
        return Text("\(named)\(company)")
    }

    private var dateChip: some View {
        HStack(spacing: 3) {
            Image(systemName: SFSymbol.Time.calendar)
                .font(.system(size: 10))
            Text(dueDayText)
                .font(AppTheme.ScaledFont.caption)
        }
        .foregroundStyle(item.isOverdue ? Color.red : Color.secondary)
    }

    private var departedMark: some View {
        HStack(spacing: 3) {
            Image(systemName: "person.crop.circle.badge.xmark")
                .font(.system(size: 10))
            Text("left")
                .font(AppTheme.ScaledFont.caption)
        }
        .foregroundStyle(.tertiary)
    }

    private var dueDayText: String {
        if AppCalendar.shared.isDateInToday(item.dueDay) { return "Today" }
        if AppCalendar.shared.isDateInYesterday(item.dueDay) { return "Yesterday" }
        return DateFormatters.shortDate.string(from: item.dueDay)
    }

    private var accessibilityLabelText: String {
        var label = "Check in with \(names.map(\.name).joined(separator: ", "))"
        if !companions.isEmpty { label += ", with \(companions.joined(separator: ", "))" }
        if !detail.isEmpty { label += ", \(detail)" }
        label += ", due \(DateFormatters.mediumDate.string(from: item.dueDay))"
        if item.isOverdue { label += ", overdue" }
        if item.hasDepartedParticipant { label += ", includes a withdrawn or transferred student" }
        if let linkedTodos { label += ", \(linkedTodos.summary)" }
        return label
    }
}

// MARK: - Day picker presentation

/// The picker as a popover on the Mac and a sheet on iOS, dismissed before
/// the write so the row it hangs off can leave the list. Gone quiet's
/// Schedule check-in opens it on the next school day (`initialDay`).
struct DayPickerPresentation: ViewModifier {
    @Binding var isPresented: Bool
    var count: Int = 1
    var initialDay: Date?
    let onPick: (Date) -> Void

    func body(content: Content) -> some View {
        #if os(macOS)
        content.popover(isPresented: $isPresented) { picker }
        #else
        content.sheet(isPresented: $isPresented) {
            picker.presentationDetents([.medium, .large])
        }
        #endif
    }

    private var picker: some View {
        WorkCheckDayPicker(count: count, initialDay: initialDay) { day in
            isPresented = false
            onPick(day)
        } onCancel: {
            isPresented = false
        }
    }
}

// MARK: - TodayView plumbing

extension TodayView {

    func checkInFollowUpRow(_ item: WorkCheckInFollowUp) -> some View {
        WorkCheckInFollowUpRow(
            item: item,
            names: followUpStudentNames(for: item),
            companions: followUpCompanionNames(for: item),
            detail: followUpDetail(for: item),
            linkedTodos: item.work.id.flatMap { viewModel.linkedTodos.byWork[$0] },
            onComplete: { completeCheckInFollowUp(item) },
            onOpen: { selectedWorkID = item.work.id },
            onReschedule: { day in rescheduleCheckInFollowUp(item, to: day) },
            onLog: { status in logCheckInFollowUp(item, as: status) }
        )
        .id(item.id)
        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
    }

    /// The children the row is about: enrolled ones through the view
    /// model's cache, departed ones from the departed lookup (the cache never
    /// holds them), each by short name ("Maya S").
    func followUpStudentNames(for item: WorkCheckInFollowUp) -> [(name: String, departed: Bool)] {
        item.countedStudentIDs.compactMap { id in
            if item.departedStudentIDs.contains(id) {
                guard let student = viewModel.departedStudentsByID[id] else { return nil }
                return (student.shortName, true)
            }
            guard viewModel.studentsByID[id] != nil else { return nil }
            return (viewModel.displayName(for: id), false)
        }
    }

    /// A linked copy's classmates, by short name; a hidden test child or an
    /// unknown id is left out.
    private func followUpCompanionNames(for item: WorkCheckInFollowUp) -> [String] {
        item.companionIDs.compactMap { id in
            if viewModel.studentsByID[id] != nil { return viewModel.displayName(for: id) }
            return viewModel.departedStudentsByID[id]?.shortName
        }
    }

    private func followUpDetail(for item: WorkCheckInFollowUp) -> String {
        let purpose = CheckInReason.displayName(forStoredPurpose: item.checkIn.purpose)
        let name = resolveLessonName(for: item.work)
        return purpose.isEmpty ? name : "\(name) · \(purpose)"
    }

    /// Done means "checked today" (`TodayCheckInFollowUpActions.markCheckedIn`).
    func completeCheckInFollowUp(_ item: WorkCheckInFollowUp) {
        do {
            try TodayCheckInFollowUpActions.markCheckedIn(item, context: viewContext, saveCoordinator: saveCoordinator)
        } catch {
            Logger.app_.warning("Failed to complete work check-in: \(error.localizedDescription)")
            // The service saves with the global alert off, so this toast is the only word of it.
            toast(PresentationFailureMessage.message(for: error, fallback: "Couldn't check that in. Try again."))
            return
        }
        viewModel.reload()
        toast("Checked in")
    }

    /// A status from the row's menu: the same write as the Scheduled strip,
    /// so the check-in is marked done and a closed row's later checks skipped.
    func logCheckInFollowUp(_ item: WorkCheckInFollowUp, as status: WorkStatus) {
        do {
            try WorkLogService.log(
                [.init(work: item.work, status: status)],
                context: viewContext, saveCoordinator: saveCoordinator
            )
        } catch {
            // The service saves with the global alert off, so this toast is the only word of it.
            toast(PresentationFailureMessage.message(for: error, fallback: "Couldn't log that work. Try again."))
            return
        }
        viewModel.reload()
        toast("Logged as \(status.displayName)")
    }

    /// The week-plan rule: the check-in date and the work's `dueAt` move together.
    func rescheduleCheckInFollowUp(_ item: WorkCheckInFollowUp, to day: Date) {
        do {
            try WorkCheckInService(context: viewContext).reschedule(item.checkIn, to: day)
        } catch {
            Logger.app_.warning("Failed to reschedule work check-in: \(error.localizedDescription)")
            toast("Couldn't move that check-in. Try again.")
            return
        }
        item.work.dueAt = day
        guard saveCoordinator.save(viewContext, reason: "Reschedule work check-in") else { return }
        viewModel.reload()
        toast("Moved to \(DateFormatters.weekdayAndDate.string(from: day))")
    }
}

// MARK: - Preview

private struct TodayViewCheckInFollowUpRowsPreview: View {
    var body: some View {
        let stack = CoreDataStack.preview
        let ctx = stack.viewContext
        let work = CDWorkModel(context: ctx)
        work.title = "Stamp Game Multiplication"
        work.studentID = UUID().uuidString
        let checkIn = CDWorkCheckIn.make(
            for: work, on: AppCalendar.addingDays(-3, to: Date()), purpose: "progressCheck", in: ctx
        )
        let item = WorkCheckInFollowUp(
            id: checkIn.id ?? UUID(), checkIn: checkIn, work: work,
            dueDay: AppCalendar.startOfDay(checkIn.date ?? Date()), isOverdue: true,
            studentIDs: [], departedStudentIDs: [UUID()]
        )
        return List {
            WorkCheckInFollowUpRow(
                item: item,
                names: [("Etty D", false)],
                companions: ["Naomi L", "Ora K"],
                detail: "Stamp Game Multiplication · Progress Check",
                onComplete: {}, onOpen: {}, onReschedule: { _ in }
            )
        }
        .previewEnvironment(using: stack)
    }
}

#Preview {
    TodayViewCheckInFollowUpRowsPreview()
}
