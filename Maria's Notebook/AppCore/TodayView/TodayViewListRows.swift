// TodayViewListRows.swift
// List row components for TodayView

import SwiftUI

// MARK: - Subtle Row Button Style

struct SubtleRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .adaptiveAnimation(.easeOut(duration: 0.15), value: configuration.isPressed)
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
                    Image(systemName: SFSymbol.Action.checkmark)
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
                    let notesPreview: String = {
                        if reminder.eventKitReminderID != nil {
                            return reminder.notes ?? ""
                        }
                        return reminder.latestUnifiedNoteText
                    }()
                    if !notesPreview.isEmpty {
                        Text(notesPreview)
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
        let reasonLabel = item.checkIn.purpose
        var label = "\(reasonLabel) for \(studentName), \(lessonName)"
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        label += ", scheduled for \(formatter.string(from: item.checkIn.date))"
        if !item.checkIn.latestUnifiedNoteText.isEmpty {
            label += ", note: \(item.checkIn.latestUnifiedNoteText)"
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

                    if !item.checkIn.latestUnifiedNoteText.isEmpty {
                        Text(item.checkIn.latestUnifiedNoteText)
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text(item.checkIn.date, style: .date)
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
        !work.latestUnifiedNoteText.isEmpty
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
                Image(systemName: SFSymbol.Text.textAlignLeft)
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

struct ScheduledMeetingListRow: View {
    let studentName: String
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.clock")
                    .font(.system(size: 14))
                    .foregroundStyle(.teal.opacity(0.8))
                    .frame(width: 20)

                Text(studentName)
                    .font(AppTheme.ScaledFont.callout)
                    .foregroundStyle(.primary)

                Spacer()

                Text("Scheduled")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.subtleRow)
        .accessibilityLabel("Meeting with \(studentName)")
        .accessibilityHint("Double tap to start meeting")
    }
}
