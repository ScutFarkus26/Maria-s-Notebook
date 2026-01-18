// TodayViewListRows.swift
// List row components for TodayView

import SwiftUI

// MARK: - List Row Components

struct ReminderListRow: View {
    let reminder: Reminder
    var onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(reminder.isCompleted ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(reminder.title)
                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .strikethrough(reminder.isCompleted)
                    if let dueDate = reminder.dueDate {
                        Text(dueDate, style: .time)
                            .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    if let notes = reminder.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: reminder.isCompleted)
    }
}

struct LessonListRow: View {
    let lessonName: String
    let studentNames: String
    let isPresented: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.book.closed").foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                if !studentNames.trimmed().isEmpty {
                    Text(studentNames)
                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                Text(lessonName)
                    .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isPresented {
                Text("Presented")
                    .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.green.opacity(0.12)))
            }
        }
    }
}

struct ContractScheduleListRow: View {
    let item: ContractScheduleItem
    let studentName: String
    let lessonName: String
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: item.planItem.reason?.icon ?? "bell").foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(studentName)
                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(lessonName)
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        Text(item.planItem.reason?.label ?? "Check-In")
                        if let note = item.planItem.note, !note.isEmpty {
                            Text("• \(note)")
                        }
                    }
                    .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Text(item.planItem.scheduledDate, style: .date)
                    .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange.opacity(0.12)))
            }
        }
        .buttonStyle(.plain)
    }
}

struct ContractFollowUpListRow: View {
    let item: ContractFollowUpItem
    let studentName: String
    let lessonName: String
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.clockwise").foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text(studentName)
                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(lessonName)
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("\(item.daysSinceTouch) days since update")
                        .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}

struct CompletionListRow: View {
    let studentName: String
    let lessonName: String
    let work: WorkModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(studentName)
                    .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(lessonName)
                    .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !work.notes.trimmed().isEmpty || (work.unifiedNotes?.isEmpty == false) {
                Image(systemName: "note.text")
                    .foregroundStyle(.secondary)
            }
        }
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

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                HStack(spacing: 4) {
                    Text(timeString)
                        .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                        .foregroundStyle(.secondary)
                    if let location = event.location, !location.isEmpty {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Image(systemName: "mappin")
                            .font(.system(size: AppTheme.FontSize.captionSmall))
                            .foregroundStyle(.secondary)
                        Text(location)
                            .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
            if event.isAllDay {
                Text("All Day")
                    .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.blue.opacity(0.12)))
            }
        }
    }
}
