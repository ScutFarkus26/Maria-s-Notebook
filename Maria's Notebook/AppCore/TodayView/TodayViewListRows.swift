// TodayViewListRows.swift
// List row components for TodayView

import SwiftUI

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

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(reminder.isCompleted ? .green : .secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(reminder.title)
                        .font(AppTheme.ScaledFont.bodySemibold)
                        .foregroundStyle(.primary)
                        .strikethrough(reminder.isCompleted)
                    if let dueDate = reminder.dueDate {
                        Text(dueDate, style: .time)
                            .font(AppTheme.ScaledFont.captionSmall)
                            .foregroundStyle(.secondary)
                    }
                    if let notes = reminder.notes, !notes.isEmpty {
                        Text(notes)
                            .font(AppTheme.ScaledFont.captionSmall)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
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
        HStack(spacing: 10) {
            Image(systemName: "text.book.closed")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                if !studentNames.trimmed().isEmpty {
                    Text(studentNames)
                        .font(AppTheme.ScaledFont.bodySemibold)
                        .foregroundStyle(.primary)
                }
                Text(lessonName)
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isPresented {
                Text("Presented")
                    .font(AppTheme.ScaledFont.captionSmallSemibold)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.green.opacity(0.12)))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint("Double tap to view lesson details")
    }
}

struct ContractScheduleListRow: View {
    let item: ContractScheduleItem
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
            HStack(spacing: 10) {
                Image(systemName: item.planItem.reason?.icon ?? "bell")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(studentName)
                        .font(AppTheme.ScaledFont.bodySemibold)
                        .foregroundStyle(.primary)
                    Text(lessonName)
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        Text(item.planItem.reason?.label ?? "Check-In")
                        if let note = item.planItem.note, !note.isEmpty {
                            Text("• \(note)")
                        }
                    }
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Text(item.planItem.scheduledDate, style: .date)
                    .font(AppTheme.ScaledFont.captionSmallSemibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange.opacity(0.12)))
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint("Double tap to view work details")
    }
}

struct ContractFollowUpListRow: View {
    let item: ContractFollowUpItem
    let studentName: String
    let lessonName: String
    var onTap: () -> Void

    private var accessibilityLabelText: String {
        "Follow-up needed for \(studentName), \(lessonName), \(item.daysSinceTouch) days since last update"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(.purple)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(studentName)
                        .font(AppTheme.ScaledFont.bodySemibold)
                        .foregroundStyle(.primary)
                    Text(lessonName)
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                    Text("\(item.daysSinceTouch) days since update")
                        .font(AppTheme.ScaledFont.captionSmall)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
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
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(studentName)
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(.primary)
                Text(lessonName)
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if hasNotes {
                Image(systemName: "note.text")
                    .foregroundStyle(.secondary)
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
            return "All Day"
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
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .foregroundStyle(.blue)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(.primary)
                HStack(spacing: 4) {
                    Text(timeString)
                        .font(AppTheme.ScaledFont.captionSmall)
                        .foregroundStyle(.secondary)
                    if let location = event.location, !location.isEmpty {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Image(systemName: "mappin")
                            .font(AppTheme.ScaledFont.captionSmall)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(location)
                            .font(AppTheme.ScaledFont.captionSmall)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
            if event.isAllDay {
                Text("All Day")
                    .font(AppTheme.ScaledFont.captionSmallSemibold)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.blue.opacity(0.12)))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelText)
    }
}
