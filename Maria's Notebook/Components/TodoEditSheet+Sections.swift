// TodoEditSheet+Sections.swift
// Schedule and priority sections for TodoEditSheet.
// Content sections: TodoEditSheet+ContentSections.swift
// Helpers & actions: TodoEditSheet+SectionHelpers.swift

import SwiftUI
import SwiftData

extension TodoEditSheet {
    // MARK: - Due Date Section

    @ViewBuilder
    var dueDateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Schedule")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack {
                Text("When")
                    .font(AppTheme.ScaledFont.body)
                Spacer()
                TodoSchedulePickerButton(
                    scheduledDate: $scheduledDate,
                    dueDate: $deadlineDate,
                    isSomeday: $isSomeday
                )
            }

            Picker("Repeats", selection: $recurrence) {
                ForEach(RecurrencePattern.allCases, id: \.self) { pattern in
                    Text(pattern.rawValue).tag(pattern)
                }
            }
            .pickerStyle(.menu)

            if recurrence != .none {
                Toggle("Repeat after completion", isOn: $repeatAfterCompletion)
                    .font(AppTheme.ScaledFont.body)
                if recurrence == .custom {
                    Stepper("Every \(customIntervalDays) days", value: $customIntervalDays, in: 1...365)
                        .font(AppTheme.ScaledFont.body)
                }
            }
        }
    }

    // MARK: - Priority Section

    @ViewBuilder
    var prioritySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Priority")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack(spacing: 8) {
                ForEach(TodoPriority.allCases, id: \.self) { priorityLevel in
                    Button {
                        adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            priority = priorityLevel
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: priorityLevel.icon)
                                .font(.system(size: 12))
                            Text(priorityLevel.rawValue)
                                .font(AppTheme.ScaledFont.body)
                                .fontWeight(priority == priorityLevel ? .semibold : .regular)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(
                                    priority == priorityLevel
                                        ? colorForPriority(priorityLevel).opacity(UIConstants.OpacityConstants.accent)
                                        : Color.secondary.opacity(UIConstants.OpacityConstants.light)
                                )
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(
                                    priority == priorityLevel
                                        ? colorForPriority(priorityLevel).opacity(0.4)
                                        : Color.clear,
                                    lineWidth: 1.5
                                )
                        }
                        .foregroundStyle(priority == priorityLevel ? colorForPriority(priorityLevel) : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    func colorForPriority(_ priority: TodoPriority) -> Color {
        switch priority {
        case .none: return .gray
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }

    // MARK: - Recurrence Section

    @ViewBuilder
    var recurrenceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Repeat")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                if recurrence != .none {
                    Image(systemName: recurrence.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(.purple)
                }
            }

            Menu {
                ForEach(RecurrencePattern.allCases, id: \.self) { pattern in
                    Button {
                        adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            recurrence = pattern
                        }
                    } label: {
                        HStack {
                            Text(pattern.description)
                            if recurrence == pattern {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(recurrence.description)
                        .font(AppTheme.ScaledFont.body)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(!hasDueDate)
            .opacity(hasDueDate ? 1.0 : 0.5)

            if !hasDueDate {
                Text("Set a due date to enable recurrence")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
