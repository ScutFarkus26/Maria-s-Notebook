// TodoDetailView.swift
// Elegant full-screen todo list view inspired by Things and Bear

import SwiftUI
import SwiftData

// MARK: - Todo Detail View

// swiftlint:disable:next type_body_length
struct TodoDetailView: View {
    @Bindable var todo: TodoItem
    @Environment(\.modelContext) private var modelContext
    @Query(sort: Student.sortByName) private var allStudentsRaw: [Student]
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames)
    private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    private var allStudents: [Student] {
        TestStudentsFilter.filterVisible(
            allStudentsRaw.uniqueByID.filter(\.isEnrolled),
            show: showTestStudents,
            namesRaw: testStudentNamesRaw
        )
    }

    let onClose: () -> Void
    let onEdit: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Title + Checkbox
                HStack(alignment: .top, spacing: 14) {
                    Button {
                        adaptiveWithAnimation(.snappy(duration: 0.2)) {
                            todo.isCompleted.toggle()
                            todo.completedAt = todo.isCompleted ? Date() : nil
                            try? modelContext.save()
                        }
                    } label: {
                        Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 28))
                            .foregroundStyle(todo.isCompleted ? .green : .secondary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)

                    Text(todo.title)
                        .font(AppTheme.ScaledFont.titleXLarge)
                        .strikethrough(todo.isCompleted)
                }

                // Students
                if !todo.studentIDs.isEmpty {
                    detailSection("Students", icon: "person.2.fill") {
                        FlowLayout(spacing: 8) {
                            ForEach(todo.studentUUIDs, id: \.self) { studentID in
                                let name = allStudents.first(where: { $0.id == studentID })
                                    .map { "\($0.firstName) \($0.lastName)" } ?? "Unknown"
                                Text(name)
                                    .font(AppTheme.ScaledFont.captionSemibold)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.accentColor.opacity(0.12))
                                    .foregroundStyle(Color.accentColor)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                // Due Date & Recurrence
                if todo.dueDate != nil || todo.scheduledDate != nil || todo.isSomeday || todo.recurrence != .none {
                    detailSection("Schedule", icon: "calendar") {
                        VStack(alignment: .leading, spacing: 10) {
                            if let scheduled = todo.scheduledDate {
                                metadataRow(
                                    icon: "star", label: "Scheduled",
                                    value: formatDate(scheduled), valueColor: .blue
                                )
                            }
                            if let dueDate = todo.dueDate {
                                metadataRow(
                                    icon: "flag.fill", label: "Deadline",
                                    value: formatDate(dueDate),
                                    valueColor: todo.isOverdue ? .red : .orange
                                )
                            }
                            if todo.isSomeday {
                                metadataRow(icon: "moon.zzz", label: "Status", value: "Someday", valueColor: .secondary)
                            }
                            if todo.recurrence != .none {
                                metadataRow(
                                    icon: todo.recurrence.icon, label: "Repeats",
                                    value: todo.recurrence.description, valueColor: .purple
                                )
                            }
                            if todo.repeatAfterCompletion {
                                metadataRow(
                                    icon: "arrow.clockwise", label: "Mode",
                                    value: "After completion", valueColor: .purple
                                )
                            }
                        }
                    }
                }

                // Priority
                if todo.priority != .none {
                    detailSection("Priority", icon: "flag.fill") {
                        HStack(spacing: 8) {
                            Circle().fill(todo.priority.color).frame(width: 10, height: 10)
                            Text(todo.priority.rawValue)
                                .font(AppTheme.ScaledFont.bodySemibold)
                                .foregroundStyle(todo.priority.color)
                        }
                    }
                }

                // Tags
                if !todo.tags.isEmpty {
                    detailSection("Tags", icon: "tag.fill") {
                        FlowLayout(spacing: 8) {
                            ForEach(todo.tags, id: \.self) { tag in
                                TagBadge(tag: tag)
                            }
                        }
                    }
                }

                // Subtasks
                let viewSubs = todo.subtasks ?? []
                if !viewSubs.isEmpty {
                    detailSection("Checklist", icon: "checklist") {
                        VStack(alignment: .leading, spacing: 2) {
                            // Progress bar
                            let completed = viewSubs.filter(\.isCompleted).count
                            let total = viewSubs.count
                            HStack(spacing: 8) {
                                ProgressView(value: Double(completed), total: Double(total))
                                    .tint(completed == total ? .green : .accentColor)
                                Text("\(completed)/\(total)")
                                    .font(AppTheme.ScaledFont.captionSemibold)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.bottom, 8)

                            ForEach(viewSubs.sorted { $0.orderIndex < $1.orderIndex }) { subtask in
                                HStack(spacing: 10) {
                                    Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 16))
                                        .foregroundStyle(subtask.isCompleted ? .green : .secondary)
                                    Text(subtask.title)
                                        .font(AppTheme.ScaledFont.body)
                                        .foregroundStyle(subtask.isCompleted ? .secondary : .primary)
                                        .strikethrough(subtask.isCompleted)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }

                // Time Tracking
                if todo.estimatedMinutes != nil || todo.actualMinutes != nil {
                    detailSection("Time", icon: "clock.fill") {
                        VStack(alignment: .leading, spacing: 8) {
                            if let est = todo.estimatedMinutes {
                                metadataRow(
                                    icon: "hourglass", label: "Estimated",
                                    value: formatMinutes(est), valueColor: .secondary
                                )
                            }
                            if let actual = todo.actualMinutes {
                                metadataRow(
                                    icon: "stopwatch", label: "Actual",
                                    value: formatMinutes(actual), valueColor: .secondary
                                )
                            }
                            if let est = todo.estimatedMinutes, let actual = todo.actualMinutes, est > 0 {
                                let variance = actual - est
                                let color: Color = variance > 0 ? .red : (variance < 0 ? .green : .secondary)
                                let sign = variance > 0 ? "+" : ""
                                let val = "\(sign)\(formatMinutes(abs(variance)))"
                                metadataRow(
                                    icon: "chart.bar", label: "Variance",
                                    value: val, valueColor: color
                                )
                            }
                        }
                    }
                }

                // Reminder
                if let reminderDate = todo.reminderDate {
                    detailSection("Reminder", icon: "bell.fill") {
                        metadataRow(
                            icon: "bell", label: "Alert at",
                            value: formatDate(reminderDate), valueColor: .yellow
                        )
                    }
                }

                // Location Reminder
                if todo.hasLocationReminder, let locationName = todo.locationName {
                    detailSection("Location", icon: "location.fill") {
                        VStack(alignment: .leading, spacing: 8) {
                            metadataRow(icon: "mappin", label: "Place", value: locationName, valueColor: .teal)
                            HStack(spacing: 12) {
                                if todo.notifyOnEntry {
                                    Label("On arrival", systemImage: "arrow.right.circle")
                                        .font(AppTheme.ScaledFont.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if todo.notifyOnExit {
                                    Label("On departure", systemImage: "arrow.left.circle")
                                        .font(AppTheme.ScaledFont.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                // Linked Work Item
                if todo.linkedWorkItemID != nil {
                    detailSection("Work Item", icon: "link") {
                        HStack(spacing: 6) {
                            Image(systemName: "briefcase.fill")
                                .foregroundStyle(.indigo)
                            Text("Linked work item")
                                .font(AppTheme.ScaledFont.body)
                                .foregroundStyle(.indigo)
                        }
                    }
                }

                // Attachments
                if todo.hasAttachments {
                    detailSection("Attachments", icon: "paperclip") {
                        Text("\(todo.attachmentPaths.count) file\(todo.attachmentPaths.count == 1 ? "" : "s")")
                            .font(AppTheme.ScaledFont.body)
                            .foregroundStyle(.secondary)
                    }
                }

                // Mood & Reflection
                if todo.hasMoodOrReflection {
                    detailSection("Mood & Reflection", icon: "face.smiling") {
                        VStack(alignment: .leading, spacing: 10) {
                            if let mood = todo.mood {
                                HStack(spacing: 8) {
                                    Text(mood.emoji)
                                        .font(AppTheme.ScaledFont.header)
                                    Text(mood.rawValue)
                                        .font(AppTheme.ScaledFont.bodySemibold)
                                        .foregroundStyle(mood.color)
                                }
                            }
                            let reflection = todo.reflectionNotes.trimmed()
                            if !reflection.isEmpty {
                                Text(reflection)
                                    .font(AppTheme.ScaledFont.body)
                                    .foregroundStyle(.secondary)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.secondary.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }

                // Notes
                if !todo.notes.isEmpty {
                    detailSection("Notes", icon: "text.alignleft") {
                        Text(todo.notes)
                            .font(AppTheme.ScaledFont.body)
                    }
                }

                // Completed timestamp
                if todo.isCompleted, let completedAt = todo.completedAt {
                    detailSection("Completed", icon: "checkmark.seal.fill") {
                        metadataRow(
                            icon: "checkmark", label: "Completed",
                            value: formatDate(completedAt), valueColor: .green
                        )
                    }
                }

                // Created timestamp
                detailSection("Created", icon: "clock.arrow.circlepath") {
                    metadataRow(
                        icon: "plus.circle", label: "Created",
                        value: formatDate(todo.createdAt), valueColor: .secondary
                    )
                }
            }
            .padding(24)
        }
        #if os(iOS)
        .background(Color(.systemGroupedBackground))
        #else
        .background(Color(nsColor: .controlBackgroundColor))
        #endif
        .navigationTitle("")
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    onClose()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
            }
            #else
            ToolbarItem(placement: .automatic) {
                Button("Back") { onClose() }
            }
            ToolbarItem(placement: .automatic) {
                Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
            }
            #endif
        }
    }

    // MARK: - Detail Helpers

    @ViewBuilder
    private func detailSection(_ title: String, icon: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            content()
        }
    }

    private func metadataRow(icon: String, label: String, value: String, valueColor: Color = .secondary) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(label)
                .font(AppTheme.ScaledFont.body)
            Spacer()
            Text(value)
                .font(AppTheme.ScaledFont.body)
                .foregroundStyle(valueColor)
        }
    }

    private func formatDate(_ date: Date) -> String {
        DateFormatters.mediumDateTime.string(from: date)
    }

    private func formatMinutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 && mins > 0 {
            return "\(hours)h \(mins)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(mins)m"
        }
    }
}
