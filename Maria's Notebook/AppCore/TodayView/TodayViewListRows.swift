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

// MARK: - Grouped Scheduled Work Row

struct GroupedScheduledWorkListRow: View {
    let items: [ScheduledWorkItem]
    let studentNames: [String]
    let lessonName: String
    let isFlexible: Bool
    var onTap: (UUID) -> Void

    @State private var isExpanded: Bool = false

    private var studentNamesDisplay: String {
        studentNames.joined(separator: ", ")
    }

    private var accessibilityLabelText: String {
        "Group check-in for \(studentNamesDisplay), \(lessonName), \(items.count) students"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main grouped row
            Button {
                if isFlexible {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                } else if let first = items.first {
                    onTap(first.work.id)
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("\(items.count)")
                                .font(.system(size: AppTheme.FontSize.captionSmall, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.orange))
                            Text(studentNamesDisplay)
                                .font(AppTheme.ScaledFont.callout)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        }
                        Text(lessonName)
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if isFlexible {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if let date = items.first?.checkIn.date {
                        Text(date, style: .date)
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.subtleRow)
            .accessibilityLabel(accessibilityLabelText)
            .accessibilityHint(isFlexible ? "Double tap to expand individual students" : "Double tap to view group check-in")

            // Expanded individual rows (flexible mode only)
            if isFlexible && isExpanded {
                VStack(spacing: 4) {
                    ForEach(Array(zip(items, studentNames)), id: \.0.id) { item, name in
                        Button {
                            onTap(item.work.id)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Text(name)
                                    .font(AppTheme.ScaledFont.caption)
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(.leading, 28)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.subtleRow)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Grouped Follow-Up Work Row

struct GroupedFollowUpWorkListRow: View {
    let items: [FollowUpWorkItem]
    let studentNames: [String]
    let lessonName: String
    let isFlexible: Bool
    var onTap: (UUID) -> Void

    @State private var isExpanded: Bool = false

    private var studentNamesDisplay: String {
        studentNames.joined(separator: ", ")
    }

    private var maxDaysSinceTouch: Int {
        items.map(\.daysSinceTouch).max() ?? 0
    }

    private var accessibilityLabelText: String {
        "Group follow-up for \(studentNamesDisplay), \(lessonName), \(maxDaysSinceTouch) days since last update"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if isFlexible {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                } else if let first = items.first {
                    onTap(first.work.id)
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("\(items.count)")
                                .font(.system(size: AppTheme.FontSize.captionSmall, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.purple))
                            Text(studentNamesDisplay)
                                .font(AppTheme.ScaledFont.callout)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        }
                        Text(lessonName)
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if isFlexible {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Text("\(maxDaysSinceTouch)d ago")
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.subtleRow)
            .accessibilityLabel(accessibilityLabelText)
            .accessibilityHint(isFlexible ? "Double tap to expand individual students" : "Double tap to view group follow-up")

            if isFlexible && isExpanded {
                VStack(spacing: 4) {
                    ForEach(Array(zip(items, studentNames)), id: \.0.id) { item, name in
                        Button {
                            onTap(item.work.id)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Text(name)
                                    .font(AppTheme.ScaledFont.caption)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(item.daysSinceTouch)d")
                                    .font(AppTheme.ScaledFont.caption)
                                    .foregroundStyle(.quaternary)
                            }
                            .padding(.leading, 28)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.subtleRow)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Todo Today Row

struct TodoTodayRow: View {
    let todo: TodoItem
    var onToggle: () -> Void
    var onTap: () -> Void

    private var accessibilityLabelText: String {
        var label = todo.title
        if todo.isCompleted {
            label = "Completed: \(label)"
        }
        if todo.isOverdue {
            label += ", overdue"
        }
        if let dueDate = todo.dueDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            label += ", due \(formatter.string(from: dueDate))"
        }
        if todo.priority != .none {
            label += ", \(todo.priority.rawValue) priority"
        }
        if let progress = todo.subtasksProgressText {
            label += ", subtasks \(progress)"
        }
        return label
    }

    private var dueDateText: String? {
        guard let dueDate = todo.dueDate else { return nil }
        if Calendar.current.isDateInToday(dueDate) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: dueDate)
        } else if Calendar.current.isDateInYesterday(dueDate) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: dueDate)
        }
    }

    private var checkboxView: some View {
        let borderColor: Color = todo.isCompleted ? .clear : priorityBorderColor
        let fillColor: Color = todo.isCompleted ? Color.green.opacity(0.15) : .clear

        return Circle()
            .strokeBorder(borderColor, lineWidth: 1.5)
            .background(Circle().fill(fillColor))
            .overlay {
                if todo.isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.green)
                }
            }
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
    }

    private var priorityBorderColor: Color {
        switch todo.priority {
        case .high: return .red.opacity(0.6)
        case .medium: return .orange.opacity(0.5)
        case .low: return .blue.opacity(0.4)
        case .none: return .secondary.opacity(0.4)
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Button(action: onToggle) {
                    checkboxView
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    Text(todo.title)
                        .font(AppTheme.ScaledFont.callout)
                        .foregroundStyle(todo.isCompleted ? .tertiary : .primary)
                        .strikethrough(todo.isCompleted, color: Color.secondary.opacity(0.5))
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        if let dateText = dueDateText {
                            HStack(spacing: 3) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 10))
                                Text(dateText)
                                    .font(AppTheme.ScaledFont.caption)
                            }
                            .foregroundStyle(todo.isOverdue ? Color.red : Color.secondary)
                        }

                        if let progress = todo.subtasksProgressText {
                            HStack(spacing: 3) {
                                Image(systemName: "checklist")
                                    .font(.system(size: 10))
                                Text(progress)
                                    .font(AppTheme.ScaledFont.caption)
                            }
                            .foregroundStyle(todo.allSubtasksCompleted ? Color.green : Color.secondary)
                        }

                        if todo.recurrence != .none {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                                .foregroundStyle(.purple.opacity(0.7))
                        }

                        if !todo.tags.isEmpty {
                            let firstName = TodoTagHelper.tagName(todo.tags[0])
                            let firstColor = TodoTagHelper.tagColor(todo.tags[0])
                            Text(firstName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(firstColor.color)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(firstColor.lightColor)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                            if todo.tags.count > 1 {
                                Text("+\(todo.tags.count - 1)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Spacer()

                // Priority indicator
                if todo.priority != .none && todo.priority != .low {
                    Circle()
                        .fill(todo.priority.color)
                        .frame(width: 7, height: 7)
                }
            }
        }
        .buttonStyle(.subtleRow)
        .sensoryFeedback(.success, trigger: todo.isCompleted)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint("Double tap to view details, swipe right to complete")
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
