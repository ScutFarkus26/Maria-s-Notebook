// TodoRowCard.swift
// Elegant todo row card inspired by Things and Bear

import OSLog
import SwiftUI
import SwiftData

// swiftlint:disable:next type_body_length
struct TodoRowCard: View {
    private static let logger = Logger.todos

    @Bindable var todo: TodoItem
    @Environment(\.modelContext) private var modelContext
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var checkboxScale: CGFloat = 1.0

    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 0) {
                // Priority left-edge bar
                if todo.priority != .none {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(priorityColor(todo.priority))
                        .frame(width: 3)
                        .padding(.vertical, 6)
                        .padding(.trailing, 11)
                } else {
                    Spacer()
                        .frame(width: 14)
                }

                // Checkbox
                Button {
                    _ = adaptiveWithAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                        checkboxScale = 0.8
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        _ = adaptiveWithAnimation(.spring(response: 0.35, dampingFraction: 0.5)) {
                            todo.isCompleted.toggle()
                            todo.completedAt = todo.isCompleted ? Date() : nil
                            checkboxScale = 1.0
                            do {
                                try modelContext.save()
                            } catch {
                                let desc = error.localizedDescription
                                Self.logger.error("Failed to save todo completion state: \(desc, privacy: .public)")
                            }
                        }
                    }
                } label: {
                    Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(todo.isCompleted ? .secondary : .tertiary)
                        .contentTransition(.symbolEffect(.replace))
                        .scaleEffect(checkboxScale)
                }
                .buttonStyle(.plain)
                #if os(iOS)
                .sensoryFeedback(.success, trigger: todo.isCompleted)
                #endif

                Spacer().frame(width: 14)

                // Content
                VStack(alignment: .leading, spacing: 3) {
                    Text(todo.title)
                        .font(AppTheme.ScaledFont.titleSmall)
                        .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                        .strikethrough(todo.isCompleted, color: .secondary.opacity(0.5))

                    if !todo.notes.isEmpty {
                        Text(todo.notes)
                            .font(AppTheme.ScaledFont.body)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    if todo.effectiveDate != nil || todo.isSomeday || !todo.tags.isEmpty || todo.recurrence != .none {
                        HStack(spacing: 6) {
                            if todo.effectiveDate != nil || todo.isSomeday {
                                TodoDateChip(todo: todo)
                            }

                            if todo.recurrence != .none {
                                HStack(spacing: 3) {
                                    Image(systemName: "repeat")
                                        .font(.system(size: 10))
                                    Text(todo.recurrence.shortLabel)
                                        .font(AppTheme.ScaledFont.captionSemibold)
                                }
                                .foregroundStyle(.purple.opacity(0.7))
                            }

                            if !todo.tags.isEmpty {
                                fittingTagBadges(todo.tags)
                            }
                        }
                        .padding(.top, 2)
                    }
                }

                Spacer(minLength: 8)

                // Subtask count
                if let progressText = todo.subtasksProgressText {
                    HStack(spacing: 3) {
                        Image(systemName: "checklist")
                            .font(.system(size: 11))
                        Text(progressText)
                            .font(AppTheme.ScaledFont.captionSemibold)
                    }
                    .foregroundStyle(todo.allSubtasksCompleted ? .green.opacity(0.7) : .secondary.opacity(0.5))
                }
            }
            .padding(.trailing, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(todo.isCompleted ? 0.5 : 1.0)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .leading) {
            Button {
                todo.scheduledDate = AppCalendar.startOfDay(Date())
                todo.isSomeday = false
                try? modelContext.save()
            } label: {
                Label("Today", systemImage: "star.fill")
            }
            .tint(.orange)

            Button {
                todo.scheduledDate = AppCalendar.addingDays(1, to: AppCalendar.startOfDay(Date()))
                todo.isSomeday = false
                try? modelContext.save()
            } label: {
                Label("Tomorrow", systemImage: "sunrise")
            }
            .tint(.orange.opacity(0.8))

            Button {
                todo.scheduledDate = nextMonday()
                todo.isSomeday = false
                try? modelContext.save()
            } label: {
                Label("+1 Week", systemImage: "calendar.badge.plus")
            }
            .tint(.purple)
        }
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button {
                togglePriority()
            } label: {
                Label("Change Priority", systemImage: "flag")
            }

            Divider()

            Menu("Move to...") {
                Button {
                    todo.scheduledDate = AppCalendar.startOfDay(Date())
                    todo.isSomeday = false
                    try? modelContext.save()
                } label: {
                    Label("Today", systemImage: "star.fill")
                }
                Button {
                    todo.scheduledDate = AppCalendar.addingDays(1, to: AppCalendar.startOfDay(Date()))
                    todo.isSomeday = false
                    try? modelContext.save()
                } label: {
                    Label("Tomorrow", systemImage: "sunrise")
                }
                Button {
                    todo.scheduledDate = nextMonday()
                    todo.isSomeday = false
                    try? modelContext.save()
                } label: {
                    Label("Next Week", systemImage: "calendar.badge.plus")
                }
                Button {
                    todo.scheduledDate = nil
                    todo.isSomeday = true
                    try? modelContext.save()
                } label: {
                    Label("Someday", systemImage: "moon.zzz")
                }
                Divider()
                Button {
                    todo.scheduledDate = nil
                    todo.dueDate = nil
                    todo.isSomeday = false
                    try? modelContext.save()
                } label: {
                    Label("Remove Date", systemImage: "xmark.circle")
                }
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func togglePriority() {
        switch todo.priority {
        case .none: todo.priority = .low
        case .low: todo.priority = .medium
        case .medium: todo.priority = .high
        case .high: todo.priority = .none
        }
        do {
            try modelContext.save()
        } catch {
            Self.logger.error("Failed to save priority change: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func priorityColor(_ priority: TodoPriority) -> Color {
        switch priority {
        case .none: return .gray
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }

    private func nextMonday() -> Date {
        let today = AppCalendar.startOfDay(Date())
        let cal = Calendar.current
        var d = cal.date(byAdding: .day, value: 1, to: today) ?? today
        while cal.component(.weekday, from: d) != 2 {
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return d
    }

    @ViewBuilder
    private func fittingTagBadges(_ tags: [String]) -> some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Array(stride(from: tags.count, through: 1, by: -1)), id: \.self) { visibleCount in
                tagBadgeRow(tags: tags, visibleCount: visibleCount)
            }

            Text("+\(tags.count)")
                .font(AppTheme.ScaledFont.captionSmallSemibold)
                .foregroundStyle(.tertiary)
        }
    }

    private func tagBadgeRow(tags: [String], visibleCount: Int) -> some View {
        let visibleTags = Array(tags.prefix(visibleCount))
        let hiddenCount = max(tags.count - visibleCount, 0)

        return HStack(spacing: 6) {
            ForEach(Array(visibleTags.enumerated()), id: \.offset) { _, tag in
                TagBadge(tag: tag, compact: true)
            }

            if hiddenCount > 0 {
                Text("+\(hiddenCount)")
                    .font(AppTheme.ScaledFont.captionSmallSemibold)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
