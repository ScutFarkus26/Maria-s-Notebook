// AttendanceExpandedView+Band.swift
// The Mac and iPad roll's band above the tiles: the count, where arrival
// stands, the one thing to do next, who isn't in yet, and the day's comings
// and goings.

import SwiftUI

extension AttendanceExpandedView {

    // MARK: - Band

    /// "17 of 22 here" large, the rest small under it; on the right, where
    /// arrival stands and the one button the moment calls for (Close Arrival
    /// & Email… near the due time, Close Arrival… before it, Email Front
    /// Desk once everyone's marked, and nothing once it has gone; with
    /// ParentLocker picked, Close Arrival & Send… and Send to ParentLocker).
    /// Under them, ParentLocker's line, the children not in yet, each a click
    /// from present, and the day's pickups, departures and returns.
    @ViewBuilder
    var arrivalBand: some View {
        if !isCompact, !viewModel.rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if !isEditing { lockedBanner }
                if isNonSchoolDay {
                    Label("Not a school day. Attendance is optional.", systemImage: "calendar.badge.minus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .bottom, spacing: AppTheme.Spacing.medium) {
                    countBlock
                    Spacer(minLength: AppTheme.Spacing.small)
                    if !hostsToolbar { inlineControls }
                    bandActions
                }
                parentLockerLine(showsProblems: true)
                if !notInYet.isEmpty { notInYetRow }
                if !dayEvents.isEmpty { dayEventsRow }
            }
            .padding(.top, AppTheme.Spacing.medium)
            .padding(.bottom, AppTheme.Spacing.compact)
            .animation(.smooth(duration: 0.3), value: viewModel.rows.map(\.status))
            .animation(.smooth(duration: 0.3), value: finishedLine)
            .animation(.smooth(duration: 0.3), value: welcomeLine)
        }
    }

    // MARK: - The count

    private var countBlock: some View {
        let rows = viewModel.rows
        let here = rows.count(where: \.isInRoom)
        return VStack(alignment: .leading, spacing: 2) {
            if viewModel.isFuture {
                Text("\(rows.count) on the roll")
                    .font(.system(.title, weight: .semibold))
            } else {
                Text("\(Text("\(here)"))\(Text(" of \(rows.count)").foregroundStyle(.secondary)) here")
                    .font(.system(.title, weight: .semibold))
                    .contentTransition(.numericText())
            }
            Group {
                if let finishedLine {
                    Label(finishedLine, systemImage: "sparkles").foregroundStyle(.primary)
                } else if let welcomeLine {
                    Label(welcomeLine, systemImage: "hand.wave.fill").foregroundStyle(.primary)
                } else if let detail = countDetail {
                    Text(detail)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .monospacedDigit()
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    /// "2 late · 1 left early · 3 absent · 3 not in yet", what's not zero.
    private var countDetail: String? {
        let rows = viewModel.rows
        let parts: [(AttendanceStatus, String)] = [
            (.tardy, "late"), (.leftEarly, "left early"), (.absent, viewModel.isFuture ? "absent ahead" : "absent"),
            (.unmarked, "not in yet")
        ]
        let text = parts.compactMap { status, word -> String? in
            if status == .unmarked && viewModel.isFuture { return nil }
            let count = rows.count { $0.status == status }
            return count > 0 ? "\(count) \(word)" : nil
        }
        return text.isEmpty ? nil : text.joined(separator: " · ")
    }

    // MARK: - Where arrival stands, and what to do

    /// The front desk's two moments (half an hour before the due time, and
    /// at it) redraw the buttons; nothing else does.
    private var bandActions: some View {
        // Read from the clock each time (see `frontDeskControl`).
        RedrawsAt(times: frontDeskChangeTimes) {
            let urgency = AttendanceEmailLog.urgency(for: date, deadlineMinutes: deadlineMinutes)
            VStack(alignment: .trailing, spacing: 6) {
                phaseLine(urgency)
                HStack(spacing: AppTheme.Spacing.small) {
                    if let title = markRestPresentTitle, canMarkToday, viewModel.phase == .arrival {
                        Button(title, action: markRestPresent)
                            .buttonStyle(.bordered)
                            .help("Marks everyone not in yet present; anyone already marked keeps their mark")
                    }
                    // Reopened while the day still reads as closed, with
                    // nobody left to mark: the way back to Late.
                    if viewModel.goesBackToLate, viewModel.offersCloseArrival(canMark: isEditing) {
                        Button("Back to Late", systemImage: "clock", action: closeArrival)
                            .buttonStyle(.bordered)
                            .help("Arrival was reopened here; back to Late, where a \(clickWord) marks a child late")
                    }
                    primaryAction(urgency)
                }
                .fixedSize()
            }
        }
    }

    /// Marks can be made on the day on screen: unlocked, a school day (or
    /// one taken anyway), and not ahead of it.
    private var canMarkToday: Bool {
        isEditing && !viewModel.isFuture
    }

    private var emailIsOpen: Bool {
        emailIsOn && !isNonSchoolDay && frontDeskSend == nil
    }

    /// The day still has to go, by whichever way the guide picked.
    private var attendanceIsOpen: Bool { emailIsOpen || parentLockerIsOpen }

    @ViewBuilder
    private func primaryAction(_ urgency: AttendanceEmailLog.Urgency) -> some View {
        let overdue = if case .overdue = urgency { true } else { false }
        if canMarkToday, viewModel.unmarkedCount > 0 {
            if viewModel.phase == .arrival, emailIsOpen, urgency != .none {
                Button("Close Arrival & Email…", systemImage: SFSymbol.Communication.envelope) {
                    confirmingCloseAndEmail = true
                }
                .buttonStyle(.borderedProminent)
                .tint(overdue ? .orange : nil)
                .keyboardShortcut(.return, modifiers: .command)
            } else if viewModel.phase == .arrival, sendsToParentLocker, viewModel.isToday {
                Button("Close Arrival & Send…", systemImage: "paperplane") { confirmingClose = true }
                    .buttonStyle(.borderedProminent)
                    .tint(overdue && parentLockerIsOpen ? .orange : nil)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Marks everyone not in yet absent, then sends the class to ParentLocker")
            } else if viewModel.phase == .arrival {
                Button("Close Arrival…") { confirmingClose = true }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Marks everyone not in yet absent; after that a click marks a child late")
            } else {
                Button("Mark \(viewModel.unmarkedCount) Absent") { confirmingClose = true }
                    .help("Marks everyone still not marked absent")
            }
        } else if emailIsOpen, !viewModel.isFuture, !viewModel.rows.isEmpty {
            frontDeskSendButton(overdue: overdue, prominent: urgency != .none || isRollComplete)
        } else if parentLockerIsOpen, !viewModel.isFuture, !viewModel.rows.isEmpty {
            parentLockerSendButton(overdue: overdue, prominent: urgency != .none || isRollComplete)
        }
    }

    /// Prominent once everyone's marked or the due time is near.
    @ViewBuilder
    private func frontDeskSendButton(overdue: Bool, prominent: Bool) -> some View {
        let menu = Menu {
            Button("Mark as Sent", systemImage: "checkmark.circle") { recordFrontDeskSend(confirmedByHand: true) }
        } label: {
            Label("Email Front Desk", systemImage: SFSymbol.Communication.envelope)
        } primaryAction: {
            prepareAttendanceEmail()
        }
        .help("Email this day's attendance to the front desk")
        if prominent {
            menu.buttonStyle(.borderedProminent).tint(overdue ? .orange : nil)
        } else {
            menu.buttonStyle(.bordered)
        }
    }

    /// "Arrival open · front desk email due 9:00 · 12 min", "Arrival closed
    /// · a click now marks Late" (with Reopen Arrival in its menu), and once
    /// the email has gone, who sent it.
    @ViewBuilder
    private func phaseLine(_ urgency: AttendanceEmailLog.Urgency) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            if viewModel.isFuture || isNonSchoolDay || !isEditing {
                EmptyView()
            } else if viewModel.phase == .late {
                Menu {
                    Button("Reopen Arrival", systemImage: "arrow.uturn.backward") {
                        withAnimation(.smooth(duration: 0.3)) { viewModel.reopenArrival() }
                    }
                } label: {
                    Label("Arrival closed · a \(clickWord) now marks Late", systemImage: "clock.fill")
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(Color.lateAmber)
                .help("Arrival is closed on this device")
            } else if viewModel.isToday {
                arrivalOpenLine(urgency)
            }
            if let frontDeskSend, !sendsToParentLocker {
                Menu {
                    Button("Send Again", systemImage: SFSymbol.Communication.envelope, action: prepareAttendanceEmail)
                } label: {
                    Label(frontDeskSummary(frontDeskSend), systemImage: "checkmark.circle.fill")
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(.green)
                .help("The front desk has this day's attendance")
            }
        }
        .font(.caption.weight(.medium))
    }

    /// Counts down the last half hour to the due time, a minute at a time.
    @ViewBuilder
    private func arrivalOpenLine(_ urgency: AttendanceEmailLog.Urgency) -> some View {
        switch urgency {
        case .due(let deadline) where attendanceIsOpen:
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                let minutes = max(1, Int(ceil(deadline.timeIntervalSinceNow / 60)))
                Label(
                    "Arrival open · \(dueWhat) due \(AttendanceClock.string(deadline)) · \(minutes) min",
                    systemImage: "clock"
                )
                .foregroundStyle(Color.lateAmber)
            }
        case .overdue(let deadline) where attendanceIsOpen:
            Label("Arrival open · \(dueWhat) was due \(AttendanceClock.string(deadline))",
                  systemImage: "exclamationmark.circle")
                .foregroundStyle(.orange)
        default:
            Label("Arrival open", systemImage: "door.left.hand.open")
                .foregroundStyle(.secondary)
        }
    }

    /// "click" on the Mac and the iPad with a pointer in mind; the iPad's
    /// tiles answer a tap all the same.
    private var clickWord: String {
        #if os(macOS)
        "click"
        #else
        "tap"
        #endif
    }

    // MARK: - Not in yet

    /// The children still unmarked on a day that has arrived, while arrival
    /// is open: each name marks them present.
    var notInYet: [AttendanceRow] {
        guard canMarkToday, viewModel.phase == .arrival, !isNonSchoolDay else { return [] }
        return viewModel.rows.filter { $0.status == .unmarked }
    }

    private var notInYetRow: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Text("Not in yet")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(notInYet) { row in
                        Button(row.student.shortName) {
                            undoably("Mark", row) { viewModel.tap($0, modelContext: viewContext) }
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .help("Mark \(row.name) present")
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Not in yet")
    }

    // MARK: - Locked

    /// A locked day says so, rather than greying buttons.
    private var lockedBanner: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Image(systemName: "lock.fill")
            Text("\(Text("Locked").bold()) · marks on this day can't change")
            Spacer(minLength: 0)
            if canLockDays {
                Button("Unlock") {
                    isEditing = true
                    setLocked(false, for: date)
                }
                .controlSize(.small)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Footer

    /// What the roll answers to, in one quiet line under the tiles.
    @ViewBuilder
    var hintFooter: some View {
        // The Attendance screen only: inside Today the roll is a glance.
        if !isCompact, hostsToolbar, isEditing, !viewModel.rows.isEmpty {
            HStack(spacing: AppTheme.Spacing.medium) {
                hint(clickWord.capitalized, viewModel.phase == .late ? "Late" : "Present (Late once arrival closes)")
                #if os(macOS)
                hint("Right-click", "absent, note, leaving early, history")
                hint("Space", "marks the selected child")
                hint("⌘Z", "undo")
                Text("type a name to jump")
                #else
                hint("Touch and hold", "absent, note, leaving early, history")
                #endif
                Spacer(minLength: 0)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.vertical, 6)
        }
    }

    private func hint(_ key: String, _ meaning: String) -> Text {
        Text("\(Text(key).bold().foregroundStyle(.primary)) \(meaning)")
    }
}
