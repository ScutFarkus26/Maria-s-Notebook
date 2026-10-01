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

    private var studentNamesDisplay: String {
        sequence.studentNames.joined(separator: ", ")
    }

    private var purposeTitle: String {
        CheckInReason.displayName(forStoredPurpose: sequence.purpose)
    }

    /// "Progress Check: Golden Beads, for Maya S, Leo B, Ana R" — everything
    /// the one-line row has to truncate.
    private var helpText: String {
        let what = "\(sequence.lessonTitle), for \(studentNamesDisplay)"
        return purposeTitle.isEmpty ? what : "\(purposeTitle): \(what)"
    }

    /// One line, like the single pill (see `WorkCheckInPill.body` for why):
    /// the purpose's icon first so every check in a day lines up on it, how
    /// many children, the lesson, then as many of their names as fit.
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: CheckInReason.iconName(forStoredPurpose: sequence.purpose))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("\(sequence.checkIns.count)")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.white)
                .monospacedDigit()
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .capsuleFill(Color.accentColor)
            Text(sequence.lessonTitle)
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .layoutPriority(1)
            Text(studentNamesDisplay)
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(
            UIConstants.CornerRadius.medium,
            fill: Color.accentColor.opacity(UIConstants.OpacityConstants.faint),
            stroke: Color.accentColor.opacity(UIConstants.OpacityConstants.light),
            lineWidth: UIConstants.StrokeWidth.thin
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .help(helpText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(helpText)
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
