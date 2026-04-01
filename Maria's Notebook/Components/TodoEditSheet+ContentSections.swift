// TodoEditSheet+ContentSections.swift
// Content-related sections: subtasks, work integration, attachments, time, reminders, mood, location.

import OSLog
import SwiftUI
import CoreData

extension TodoEditSheet {
    // MARK: - Subtasks Section

    @ViewBuilder
    var subtasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Checklist")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                let subtaskItems = (todo.subtasks as? Set<CDTodoSubtaskEntity>) ?? []
                if !subtaskItems.isEmpty {
                    Text(todo.subtasksProgressText ?? "")
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.secondary)
                }

                Button {
                    addSubtask()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }

            let allSubtaskItems = (todo.subtasks as? Set<CDTodoSubtaskEntity>) ?? []
            if allSubtaskItems.isEmpty {
                Text("No checklist items")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .padding(.vertical, 8)
            } else {
                let sortedSubtasks = allSubtaskItems.sorted { $0.orderIndex < $1.orderIndex }
                VStack(spacing: 6) {
                    ForEach(sortedSubtasks, id: \.objectID) { subtask in
                        SubtaskRow(
                            subtask: subtask,
                            onToggle: { toggleSubtask(subtask) },
                            onDelete: { deleteSubtask(subtask) },
                            onUpdate: { newTitle in updateSubtask(subtask, title: newTitle) }
                        )
                    }
                    .onMove { source, destination in
                        reorderSubtasks(from: source, to: destination)
                    }
                }
            }
        }
    }

    // MARK: - Work Integration Section

    @ViewBuilder
    var workIntegrationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Work Integration")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            if todo.linkedWorkItemID != nil {
                HStack(spacing: 10) {
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.indigo)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Linked to Work Item")
                            .font(AppTheme.ScaledFont.bodySemibold)
                        Text("This todo is connected to a work item")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        todo.linkedWorkItemID = nil
                        if let context = todo.managedObjectContext {
                            do {
                                try context.save()
                            } catch {
                                Logger.todos.error("[\(#function)] Failed to save todo: \(error)")
                            }
                        }
                    } label: {
                        Text("Unlink")
                            .font(AppTheme.ScaledFont.captionSemibold)
                            .foregroundStyle(AppColors.destructive)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(Color.indigo.opacity(UIConstants.OpacityConstants.light))
                .cornerRadius(8)
            } else {
                Button {
                    createWorkItemFromTodo()
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                        Text("Create Work Item")
                            .font(AppTheme.ScaledFont.bodySemibold)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.indigo)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(UIConstants.OpacityConstants.trace))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Text("Convert this todo into a work item for tracking")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Attachments Section

    @ViewBuilder
    var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Attachments")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                Button {
                    isShowingFileImporter = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.brown)
                }
                .buttonStyle(.plain)
            }

            if todo.attachmentPathsArray.isEmpty {
                Text("No attachments")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(todo.attachmentPathsArray.enumerated()), id: \.offset) { index, path in
                        HStack(spacing: 10) {
                            Image(systemName: fileIcon(for: path))
                                .font(.system(size: 20))
                                .foregroundStyle(.brown)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(fileName(from: path))
                                    .font(AppTheme.ScaledFont.body)
                                    .lineLimit(1)
                                Text(fileSize(for: path))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                removeAttachment(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.red.opacity(UIConstants.OpacityConstants.prominent))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(Color.primary.opacity(UIConstants.OpacityConstants.trace))
                        .cornerRadius(8)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            let url = URL(fileURLWithPath: path)
                            if FileManager.default.fileExists(atPath: path) {
                                previewingAttachmentURL = url
                            }
                        }
                    }
                }
            }

            Text("Tap + to attach files or images")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - CDReminder Section

    @ViewBuilder
    var reminderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Reminder")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                Toggle("", isOn: $hasReminder)
                    .labelsHidden()
            }

            if hasReminder {
                VStack(spacing: 12) {
                    DatePicker(
                        "Remind me at",
                        selection: $reminderDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)

                    if isSchedulingNotification {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Scheduling notification...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Show reminder info
                    HStack(spacing: 8) {
                        Image(systemName: "bell.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                        Text(formatReminderDate(reminderDate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.yellow.opacity(UIConstants.OpacityConstants.light))
                    .cornerRadius(8)
                }
            } else {
                Text("No reminder set")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
    }

    func formatReminderDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let timeStr = DateFormatters.shortTime.string(from: date)
        if calendar.isDateInToday(date) {
            return "Today at \(timeStr)"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow at \(timeStr)"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            return "\(DateFormatters.weekdayFull.string(from: date)) at \(timeStr)"
        } else {
            return "\(DateFormatters.shortMonthDay.string(from: date)) at \(timeStr)"
        }
    }

}
