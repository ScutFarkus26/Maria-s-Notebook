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
    /// Everyone on the work, owner first; `departed` styles the name and adds the mark.
    let names: [(name: String, departed: Bool)]
    /// Work title or lesson name, plus the check-in's purpose when it has one.
    let detail: String
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

    /// "Check in with Ora, Naomi" — departed names in tertiary.
    private var titleLine: Text {
        names.enumerated().reduce(Text("Check in with ")) { text, pair in
            let (index, entry) = pair
            let name = entry.departed ? Text(entry.name).foregroundStyle(.tertiary) : Text(entry.name)
            return index > 0 ? Text("\(text), \(name)") : Text("\(text)\(name)")
        }
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
        if !detail.isEmpty { label += ", \(detail)" }
        label += ", due \(DateFormatters.mediumDate.string(from: item.dueDay))"
        if item.isOverdue { label += ", overdue" }
        if item.hasDepartedParticipant { label += ", includes a withdrawn or transferred student" }
        return label
    }
}

// MARK: - Day picker presentation

/// The picker as a popover on the Mac and a sheet on iOS, dismissed before
/// the write so the row it hangs off can leave the list.
private struct DayPickerPresentation: ViewModifier {
    @Binding var isPresented: Bool
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
        WorkCheckDayPicker(count: 1) { day in
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
            detail: followUpDetail(for: item),
            onComplete: { completeCheckInFollowUp(item) },
            onOpen: { selectedWorkID = item.work.id },
            onReschedule: { day in rescheduleCheckInFollowUp(item, to: day) },
            onLog: { status in logCheckInFollowUp(item, as: status) }
        )
        .id(item.id)
        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
    }

    /// Enrolled children through the view model's cache; departed ones by
    /// first name from the departed lookup, since the cache never holds them.
    func followUpStudentNames(for item: WorkCheckInFollowUp) -> [(name: String, departed: Bool)] {
        item.studentIDs.compactMap { id in
            if item.departedStudentIDs.contains(id) {
                guard let student = viewModel.departedStudentsByID[id] else { return nil }
                return (student.firstName, true)
            }
            guard viewModel.studentsByID[id] != nil else { return nil }
            return (viewModel.displayName(for: id), false)
        }
    }

    private func followUpDetail(for item: WorkCheckInFollowUp) -> String {
        let purposeRaw = item.checkIn.purpose.trimmed()
        let purpose = CheckInReason(rawValue: purposeRaw)?.purpose ?? purposeRaw
        let name = resolveLessonName(for: item.work)
        return purpose.isEmpty ? name : "\(name) · \(purpose)"
    }

    /// Done means "checked today": the service moves the check-in's date to
    /// now, so the work calendar shows the day it was checked, not the day it
    /// was due. That is the existing service rule, kept deliberately.
    func completeCheckInFollowUp(_ item: WorkCheckInFollowUp) {
        do {
            try WorkCheckInService(context: viewContext).markCompleted(item.checkIn, note: nil, at: Date())
        } catch {
            Logger.app_.warning("Failed to complete work check-in: \(error.localizedDescription)")
            return
        }
        guard saveCoordinator.save(viewContext, reason: "Complete work check-in") else { return }
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
            Logger.app_.warning("Failed to log work status: \(error.localizedDescription)")
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
                names: [("Etty", false), ("Naomi", true)],
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
