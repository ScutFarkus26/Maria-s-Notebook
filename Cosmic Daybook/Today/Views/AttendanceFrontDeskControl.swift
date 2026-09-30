// AttendanceFrontDeskControl.swift
// The attendance screen's front-desk email control.

import SwiftUI

/// The front-desk email, which the office needs by the due time (9:00 unless
/// changed in Settings › Communication).
///
/// Until it goes: **Email Front Desk**, prominent once everyone's marked;
/// from half an hour before the due time with children still unmarked,
/// **Mark Rest Absent & Email**; after the due time, the same in orange, saying
/// it's late. Mark as Sent is in its menu for when the front desk was told
/// another way. Once the day's email has gone (from this device, another of
/// the guide's, or an assistant's phone), who sent it and when, with "(late)"
/// after the due time, and Send Again.
struct AttendanceFrontDeskControl: View {
    /// "Sent 8:42 AM by Sarah", once the day's email has gone.
    let sentSummary: String?
    let isRollComplete: Bool
    let urgency: AttendanceEmailLog.Urgency
    let onSend: () -> Void
    /// Mark everyone still unmarked absent, then send (asks first).
    let onMarkRestAbsentAndSend: () -> Void
    let onMarkSent: () -> Void

    var body: some View {
        if let sentSummary {
            Menu {
                Button("Send Again", systemImage: SFSymbol.Communication.envelope, action: onSend)
            } label: {
                Label(sentSummary, systemImage: "checkmark.circle.fill")
            }
            .menuIndicator(.hidden)
            .buttonStyle(.bordered)
            .tint(.green)
            .fixedSize()
            .help("The front desk has this day's attendance")
            .accessibilityLabel("Front desk email: \(sentSummary)")
        } else if !isRollComplete, urgency != .none {
            sendMenu("Mark Rest Absent & Email", action: onMarkRestAbsentAndSend)
                .buttonStyle(.borderedProminent)
                .tint(isOverdue ? .orange : nil)
        } else if isRollComplete {
            sendMenu("Email Front Desk", action: onSend)
                .buttonStyle(.borderedProminent)
                .tint(isOverdue ? .orange : nil)
        } else {
            sendMenu("Email Front Desk", action: onSend)
                .buttonStyle(.bordered)
        }
    }

    private var isOverdue: Bool {
        if case .overdue = urgency { return true }
        return false
    }

    /// "Due by 9:00 AM" or "Late: due 9:00 AM", for the button's help and label.
    private var dueNote: String? {
        switch urgency {
        case .none: return nil
        case .due(let deadline): return "Due by \(deadline.formatted(date: .omitted, time: .shortened))"
        case .overdue(let deadline): return "Late: due \(deadline.formatted(date: .omitted, time: .shortened))"
        }
    }

    private func sendMenu(_ title: String, action: @escaping () -> Void) -> some View {
        Menu {
            Button("Mark as Sent", systemImage: "checkmark.circle", action: onMarkSent)
        } label: {
            Label(dueNote.map { "\(title) · \($0)" } ?? title, systemImage: SFSymbol.Communication.envelope)
        } primaryAction: {
            action()
        }
        .fixedSize()
        .help(dueNote ?? "Email this day's attendance to the front desk")
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct AttendanceFrontDeskControlPreview: View {
    var body: some View {
        let nine = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
        VStack(spacing: 16) {
            AttendanceFrontDeskControl(
                sentSummary: nil, isRollComplete: false, urgency: .none,
                onSend: {}, onMarkRestAbsentAndSend: {}, onMarkSent: {}
            )
            AttendanceFrontDeskControl(
                sentSummary: nil, isRollComplete: false, urgency: .due(nine),
                onSend: {}, onMarkRestAbsentAndSend: {}, onMarkSent: {}
            )
            AttendanceFrontDeskControl(
                sentSummary: nil, isRollComplete: true, urgency: .overdue(nine),
                onSend: {}, onMarkRestAbsentAndSend: {}, onMarkSent: {}
            )
            AttendanceFrontDeskControl(
                sentSummary: "Sent 8:42 AM by Sarah", isRollComplete: true, urgency: .none,
                onSend: {}, onMarkRestAbsentAndSend: {}, onMarkSent: {}
            )
        }
        .padding()
    }
}

#Preview {
    AttendanceFrontDeskControlPreview()
}
