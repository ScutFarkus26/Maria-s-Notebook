//
//  PresentationStudentRow.swift
//  Maria's Notebook
//
//  Reusable student row for presentation sheets
//

import SwiftUI

struct PresentationStudentRow: View {
    let student: Student
    @Binding var entry: UnifiedPostPresentationSheet.StudentEntry
    @Binding var isExpanded: Bool
    let suggestedWorkItems: [String]
    let nextLesson: Lesson?
    @Binding var isUnlockSelected: Bool
    let defaultCheckInDate: Date
    let defaultDueDate: Date

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            headerRow

            // Expanded content
            if isExpanded {
                expandedContent
            }
        }
    }

    private var headerRow: some View {
        Button {
            adaptiveWithAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                Text(StudentFormatter.displayName(for: student))
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(.primary)

                Spacer()

                understandingIndicator

                HStack(spacing: 4) {
                    if !entry.observation.isEmpty || !entry.assignment.isEmpty {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppColors.success)
                            .font(.system(size: 14))
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: isExpanded ? 12 : 8, style: .continuous)
                    .fill(Color.primary.opacity(isExpanded ? 0.06 : 0.03))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var understandingIndicator: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Circle()
                    .fill(
                        understandingColor(for: entry.understandingLevel)
                            .opacity(i <= entry.understandingLevel ? 1.0 : 0.2)
                    )
                    .frame(width: 8, height: 8)
            }
        }
    }

    private var expandedContent: some View {
        VStack(spacing: 12) {
            understandingPicker
            observationField
            assignmentField
            scheduleToggles

            if nextLesson != nil {
                Divider().padding(.vertical, 8)
                nextLessonSection
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .padding(.top, -4)
    }

    private var understandingPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Understanding")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { level in
                    Button {
                        entry.understandingLevel = level
                    } label: {
                        Circle()
                            .fill(understandingColor(for: level).opacity(
                                entry.understandingLevel >= level ? 1.0 : 0.2
                            ))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Text(understandingLabel(for: entry.understandingLevel))
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var observationField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Observation")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)

            TextField("Note about this student...", text: $entry.observation, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
        }
    }

    private var assignmentField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Follow-up Work")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)

            TextField("Assignment for this student...", text: $entry.assignment, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)

            if !suggestedWorkItems.isEmpty && entry.assignment.isEmpty {
                suggestedWorkButtons
            }
        }
    }

    private var suggestedWorkButtons: some View {
        HStack(spacing: 6) {
            ForEach(Array(suggestedWorkItems.prefix(3).enumerated()), id: \.offset) { _, suggestion in
                Button {
                    entry.assignment = suggestion
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles").font(.system(size: 9))
                        let truncated = suggestion.count > 20 ? String(suggestion.prefix(20)) + "..." : suggestion
                        Text(truncated).lineLimit(1)
                    }
                    .font(AppTheme.ScaledFont.captionSmallSemibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule(style: .continuous).fill(Color.accentColor.opacity(0.08)))
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var scheduleToggles: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Check-in")
                    .font(AppTheme.ScaledFont.captionSmallSemibold)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Button {
                        entry.checkInDate = entry.checkInDate == nil ? defaultCheckInDate : nil
                    } label: {
                        Image(systemName: entry.checkInDate != nil ? "checkmark.square.fill" : "square")
                            .foregroundStyle(entry.checkInDate != nil ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)

                    if entry.checkInDate != nil {
                        DatePicker("", selection: Binding(
                            get: { entry.checkInDate ?? defaultCheckInDate },
                            set: { entry.checkInDate = $0 }
                        ), displayedComponents: .date)
                        .labelsHidden()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Due Date")
                    .font(AppTheme.ScaledFont.captionSmallSemibold)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Button {
                        entry.dueDate = entry.dueDate == nil ? defaultDueDate : nil
                    } label: {
                        Image(systemName: entry.dueDate != nil ? "checkmark.square.fill" : "square")
                            .foregroundStyle(entry.dueDate != nil ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)

                    if entry.dueDate != nil {
                        DatePicker("", selection: Binding(
                            get: { entry.dueDate ?? defaultDueDate },
                            set: { entry.dueDate = $0 }
                        ), displayedComponents: .date)
                        .labelsHidden()
                    }
                }
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var nextLessonSection: some View {
        if let nextLesson = nextLesson {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Next Lesson")
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                HStack(spacing: 8) {
                    Button {
                        isUnlockSelected.toggle()
                    } label: {
                        Image(systemName: isUnlockSelected ? "checkmark.square.fill" : "square")
                            .foregroundStyle(isUnlockSelected ? .green : .secondary)
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Unlock: \(nextLesson.name)")
                            .font(AppTheme.ScaledFont.captionSmall)
                            .foregroundStyle(.primary)

                        Text(isUnlockSelected ? "Will be unlocked when you click Done" : "Lesson will remain blocked")
                            .font(AppTheme.ScaledFont.captionSmall)
                            .foregroundStyle(isUnlockSelected ? .green : .secondary)
                    }

                    Spacer()
                }
            }
        }
    }

    private func understandingColor(for level: Int) -> Color {
        switch level {
        case 1: return .red
        case 2: return .orange
        case 3: return .yellow
        case 4: return .green
        case 5: return .blue
        default: return .gray
        }
    }

    private func understandingLabel(for level: Int) -> String {
        switch level {
        case 1: return "Struggling"
        case 2: return "Needs Support"
        case 3: return "Developing"
        case 4: return "Proficient"
        case 5: return "Mastered"
        default: return ""
        }
    }
}
