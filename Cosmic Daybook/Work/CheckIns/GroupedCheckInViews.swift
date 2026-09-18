// GroupedCheckInViews.swift
// The calendar's check-in band: the merged pill (the per-child sheet behind it
// is `WorkLogSheet`) and the prompt a dropped work card raises.
//
// Both moved here from the retired work-only calendar (WorkAgendaCalendarPane /
// WorkAgendaDayColumn) when the two day-column calendars merged. They render
// `CalendarCheckInGroup`, so they no longer belong to any one day column.

import CoreData
import SwiftUI

// MARK: - Grouped Pill

/// A pill that consolidates multiple check-ins for the same lesson and purpose into one row
struct GroupedWorkCheckInPill: View {
    let sequence: CalendarCheckInGroup
    var onTap: (() -> Void)?

    private var purposeIcon: String {
        let purpose = sequence.purpose.lowercased()
        if purpose.contains("progress") || purpose.contains("check") {
            return "checkmark.circle"
        } else if purpose.contains("due") {
            return "calendar.badge.exclamationmark"
        } else if purpose.contains("assessment") {
            return "chart.bar"
        } else if purpose.contains("follow") {
            return "arrow.turn.down.right"
        } else {
            return "calendar"
        }
    }

    private var studentNamesDisplay: String {
        sequence.studentNames.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // CDStudent count badge
                Text("\(sequence.checkIns.count)")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor))
                Text(sequence.lessonTitle)
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            Text(studentNamesDisplay)
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if !sequence.purpose.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: purposeIcon)
                        .foregroundStyle(.secondary)
                    Text(sequence.purpose)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.small)
        .padding(.vertical, AppTheme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large)
                .fill(Color.accentColor.opacity(UIConstants.OpacityConstants.faint))
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large)
                .stroke(
                    Color.accentColor.opacity(UIConstants.OpacityConstants.light),
                    lineWidth: UIConstants.StrokeWidth.thin
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }
}

/// Asks what a dropped work card's check-in is for. Kept deliberately: this is
/// the only point at which a check-in's purpose is captured, and a check-in
/// without one tells the guide nothing later.
struct PlanPromptSheetView: View {
    let prompt: WorkCheckInPlanPrompt
    let onCancel: () -> Void
    let onSave: (String, String, Bool) -> Void
    @State private var reason: String
    @State private var note: String
    @State private var studentInitiated: Bool
    init(
        prompt: WorkCheckInPlanPrompt,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String, String, Bool) -> Void
    ) {
        self.prompt = prompt
        self.onCancel = onCancel
        self.onSave = onSave
        reason = prompt.reason
        note = prompt.note
        studentInitiated = prompt.studentInitiated
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Schedule Work").font(.headline)
            Text(prompt.date, style: .date).font(.subheadline).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                Picker("Purpose", selection: $reason) {
                    // Phase 6: Simple string-based purposes
                    Text("Progress Check").tag("progressCheck")
                    Text("Assessment").tag("assessment")
                    Text("Due Date").tag("dueDate")
                }
                .pickerStyle(.segmented)
            }
            Toggle("Student requested this", isOn: $studentInitiated)
                #if os(macOS)
                .toggleStyle(.checkbox)
                #endif
            TextField("Optional note", text: $note)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                .onSubmit { onSave(reason, note, studentInitiated) }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save") { onSave(reason, note, studentInitiated) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        #if os(macOS)
        .frame(minWidth: 520)
        .presentationSizingFitted()
        #endif
    }
}
