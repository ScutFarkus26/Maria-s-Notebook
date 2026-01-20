// TodayViewListRows.swift
// List row components for TodayView

import SwiftUI

// MARK: - Subtle Row Button Style

struct SubtleRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == SubtleRowButtonStyle {
    static var subtleRow: SubtleRowButtonStyle { SubtleRowButtonStyle() }
}

// MARK: - List Row Components

struct ReminderListRow: View {
    let reminder: Reminder
    var onToggle: () -> Void

    private var accessibilityLabelText: String {
        var label = reminder.title
        if reminder.isCompleted {
            label = "Completed: \(label)"
        }
        if let dueDate = reminder.dueDate {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            label += ", due at \(formatter.string(from: dueDate))"
        }
        return label
    }

    private var checkboxView: some View {
        let borderColor: Color = reminder.isCompleted ? .clear : .secondary.opacity(0.4)
        let fillColor: Color = reminder.isCompleted ? Color.accentColor.opacity(0.15) : .clear

        return Circle()
            .strokeBorder(borderColor, lineWidth: 1.5)
            .background(Circle().fill(fillColor))
            .overlay {
                if reminder.isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                checkboxView

                VStack(alignment: .leading, spacing: 4) {
                    Text(reminder.title)
                        .font(AppTheme.ScaledFont.callout)
                        .foregroundStyle(reminder.isCompleted ? .tertiary : .primary)
                        .strikethrough(reminder.isCompleted, color: Color.secondary.opacity(0.5))
                    if let dueDate = reminder.dueDate {
                        Text(dueDate, style: .time)
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if let notes = reminder.notes, !notes.isEmpty {
                        Text(notes)
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.subtleRow)
        .sensoryFeedback(.success, trigger: reminder.isCompleted)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint(reminder.isCompleted ? "Double tap to mark as incomplete" : "Double tap to mark as complete")
        .accessibilityAddTraits(reminder.isCompleted ? .isSelected : [])
    }
}

struct LessonListRow: View {
    let lessonName: String
    let studentNames: String
    let isPresented: Bool

    private var accessibilityLabelText: String {
        var label = "Lesson: \(lessonName)"
        if !studentNames.trimmed().isEmpty {
            label += ", for \(studentNames)"
        }
        if isPresented {
            label += ", presented"
        }
        return label
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if !studentNames.trimmed().isEmpty {
                    Text(studentNames)
                        .font(AppTheme.ScaledFont.callout)
                        .foregroundStyle(isPresented ? .tertiary : .primary)
                }
                Text(lessonName)
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if isPresented {
                Text("Done")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint("Double tap to view lesson details")
    }
}

struct ScheduledWorkListRow: View {
    let item: ScheduledWorkItem
    let studentName: String
    let lessonName: String
    var onTap: () -> Void

    private var accessibilityLabelText: String {
        let reasonLabel = item.planItem.reason?.label ?? "Check-in"
        var label = "\(reasonLabel) for \(studentName), \(lessonName)"
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        label += ", scheduled for \(formatter.string(from: item.planItem.scheduledDate))"
        if let note = item.planItem.note, !note.isEmpty {
            label += ", note: \(note)"
        }
        return label
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(studentName)
                        .font(AppTheme.ScaledFont.callout)
                        .foregroundStyle(.primary)
                    Text(lessonName)
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.tertiary)

                    if let note = item.planItem.note, !note.isEmpty {
                        Text(note)
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text(item.planItem.scheduledDate, style: .date)
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.subtleRow)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint("Double tap to view work details")
    }
}

struct FollowUpWorkListRow: View {
    let item: FollowUpWorkItem
    let studentName: String
    let lessonName: String
    var onTap: () -> Void

    private var accessibilityLabelText: String {
        "Follow-up needed for \(studentName), \(lessonName), \(item.daysSinceTouch) days since last update"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(studentName)
                        .font(AppTheme.ScaledFont.callout)
                        .foregroundStyle(.primary)
                    Text(lessonName)
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text("\(item.daysSinceTouch)d ago")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.subtleRow)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint("Double tap to view work details and add follow-up")
    }
}

struct CompletionListRow: View {
    let studentName: String
    let lessonName: String
    let work: WorkModel

    private var hasNotes: Bool {
        !work.notes.trimmed().isEmpty || (work.unifiedNotes?.isEmpty == false)
    }

    private var accessibilityLabelText: String {
        var label = "Completed: \(lessonName) by \(studentName)"
        if hasNotes {
            label += ", has notes"
        }
        return label
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(studentName)
                    .font(AppTheme.ScaledFont.callout)
                    .foregroundStyle(.tertiary)
                Text(lessonName)
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.quaternary)
            }
            Spacer()
            if hasNotes {
                Image(systemName: "text.alignleft")
                    .font(.caption)
                    .foregroundStyle(.quaternary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint("Double tap to view completion details")
    }
}

struct CalendarEventListRow: View {
    let event: CalendarEvent

    private var timeString: String {
        if event.isAllDay {
            return "All day"
        } else {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            return formatter.string(from: event.startDate)
        }
    }

    private var accessibilityLabelText: String {
        var label = "Calendar event: \(event.title)"
        if event.isAllDay {
            label += ", all day"
        } else {
            label += ", at \(timeString)"
        }
        if let location = event.location, !location.isEmpty {
            label += ", at \(location)"
        }
        return label
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(AppTheme.ScaledFont.callout)
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text(timeString)
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.tertiary)
                    if let location = event.location, !location.isEmpty {
                        Text("·")
                            .foregroundStyle(.quaternary)
                        Text(location)
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelText)
    }
}
