// GroupedCheckInViews.swift
// The calendar's check-in band: the merged pill and the per-child sheet behind it.
//
// Both moved here from the retired work-only calendar (WorkAgendaCalendarPane /
// WorkAgendaDayColumn) when the two day-column calendars merged. They render
// `CalendarCheckInGroup`, so they no longer belong to any one day column.

import CoreData
import OSLog
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

// MARK: - Grouped Check-In Detail Sheet

/// Shown when tapping a merged pill — lists all students sharing the same lesson/purpose check-in.
/// Styled like the Work Items column of the post-presentation workflow sheet.
struct GroupedCheckInDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext

    let sequence: CalendarCheckInGroup
    let onSelectWork: (UUID) -> Void

    private var purposeIcon: String {
        let p = sequence.purpose.lowercased()
        if p.contains("progress") || p.contains("check") {
            return "checkmark.circle"
        } else if p.contains("due") {
            return "calendar.badge.exclamationmark"
        } else if p.contains("assessment") {
            return "chart.bar"
        } else if p.contains("follow") {
            return "arrow.turn.down.right"
        } else {
            return "calendar"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text(sequence.lessonTitle)
                        .font(.title2.weight(.semibold))
                    HStack(spacing: 6) {
                        if !sequence.purpose.isEmpty {
                            Label(sequence.purpose, systemImage: purposeIcon)
                                .foregroundStyle(.secondary)
                            Text("·").foregroundStyle(.tertiary)
                        }
                        Text(sequence.sortDate, style: .date)
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 14)

                Divider()

                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(
                            Array(zip(sequence.checkIns, sequence.studentNames)),
                            id: \.0.id
                        ) { checkIn, studentName in
                            studentRow(checkIn: checkIn, studentName: studentName)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("\(sequence.checkIns.count) Students")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 340)
        .presentationSizingFitted()
        #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private func studentRow(checkIn: CDWorkCheckIn, studentName: String) -> some View {
        let work: CDWorkModel? = checkIn.workID.asUUID.flatMap { id in
            let request = CDFetchRequest(CDWorkModel.self)
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            return modelContext.safeFetchFirst(request)
        }
        return CheckInStudentRow(
            checkIn: checkIn,
            work: work,
            studentName: studentName,
            onOpen: {
                if let workID = checkIn.workID.asUUID { onSelectWork(workID) }
            }
        )
    }

}

// MARK: - Check-In CDStudent Row

/// A single student row inside GroupedCheckInDetailSheet.
/// Owns its own note state so the text field is editable and saves back to the check-in.
private struct CheckInStudentRow: View {
    private static let logger = Logger.work

    @Environment(\.managedObjectContext) private var modelContext

    let checkIn: CDWorkCheckIn
    let work: CDWorkModel?
    let studentName: String
    let onOpen: () -> Void

    @State private var noteText: String
    @State private var saveTask: Task<Void, Never>?

    init(checkIn: CDWorkCheckIn, work: CDWorkModel?, studentName: String, onOpen: @escaping () -> Void) {
        self.checkIn = checkIn
        self.work = work
        self.studentName = studentName
        self.onOpen = onOpen
        _noteText = State(initialValue: checkIn.latestUnifiedNoteText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Name row + status dots + open button
            HStack(spacing: 8) {
                Text(studentName)
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(.primary)
                if checkIn.studentInitiated {
                    Image(systemName: "person.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Student requested this check-in")
                }
                Spacer()
                if let work {
                    statusDots(for: work)
                }
                Button(action: onOpen) {
                    Image(systemName: "arrow.forward.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Inline note field
            TextField("Note about this student…", text: $noteText, axis: .vertical)
                .font(AppTheme.ScaledFont.caption)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
                .onChange(of: noteText) { _, newValue in
                    // Debounce saves so we don't write on every keystroke
                    saveTask?.cancel()
                    saveTask = Task {
                        try? await Task.sleep(for: .milliseconds(600))
                        guard !Task.isCancelled else { return }
                        checkIn.setLegacyNoteText(newValue, in: modelContext)
                        do {
                            try modelContext.save()
                        } catch {
                            Self.logger.warning("Failed to save note: \(error)")
                        }
                    }
                }
        }
        .padding(.horizontal, UIConstants.contentHorizontalPadding)
        .padding(.vertical, AppTheme.Spacing.compact)
        .background(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
        .clipShape(RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous))
        .padding(.horizontal, UIConstants.dropZoneInnerPadding)
        .padding(.vertical, AppTheme.Spacing.xxsmall)
    }

    @ViewBuilder
    private func statusDots(for work: CDWorkModel) -> some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { i in
                Circle()
                    .fill(dotColor(for: work).opacity(i <= dotCount(for: work) ? 1.0 : 0.18))
                    .frame(width: 7, height: 7)
            }
        }
    }

    private func dotCount(for work: CDWorkModel) -> Int {
        switch work.status {
        case .active: return 2
        case .review: return 4
        case .complete: return 5
        }
    }

    private func dotColor(for work: CDWorkModel) -> Color {
        switch work.status {
        case .active: return .orange
        case .review: return .green
        case .complete: return .blue
        }
    }
}

/// Asks what a dropped work card's check-in is for. Kept deliberately: this is
/// the only point at which a check-in's purpose is captured, and a check-in
/// without one tells the guide nothing later.
struct PlanPromptSheetView: View {
    let prompt: WorkCheckInPlanPrompt
    let onCancel: () -> Void
    let onSave: (String, String, Bool) -> Void
    @State private var reason: String = "progressCheck"
    @State private var note: String = ""
    @State private var studentInitiated: Bool = false
    init(
        prompt: WorkCheckInPlanPrompt,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String, String, Bool) -> Void
    ) {
        self.prompt = prompt
        self.onCancel = onCancel
        self.onSave = onSave
        _reason = State(initialValue: prompt.reason)
        _note = State(initialValue: prompt.note)
        _studentInitiated = State(initialValue: prompt.studentInitiated)
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
