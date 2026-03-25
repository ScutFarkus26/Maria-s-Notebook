// TodoEditSheet+SectionHelpers.swift
// Attachment helpers, subtask operations, and save/action methods for TodoEditSheet.

import OSLog
import SwiftUI
import SwiftData

extension TodoEditSheet {
    private static let logger = Logger.todos

    // MARK: - Attachment Helpers

    func fileIcon(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "heic", "gif":
            return "photo"
        case "pdf":
            return "doc.fill"
        case "doc", "docx":
            return "doc.text.fill"
        case "txt":
            return "doc.plaintext"
        default:
            return "doc.fill"
        }
    }

    func fileName(from path: String) -> String {
        (path as NSString).lastPathComponent
    }

    func fileSize(for path: String) -> String {
        let attrs: [FileAttributeKey: Any]
        do {
            attrs = try FileManager.default.attributesOfItem(atPath: path)
        } catch {
            Self.logger.error("[\(#function)] Failed to get file attributes: \(error)")
            return "Unknown size"
        }
        guard let size = attrs[.size] as? Int64 else {
            return "Unknown size"
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    func removeAttachment(at index: Int) {
        guard index < todo.attachmentPaths.count else { return }
        todo.attachmentPaths.remove(at: index)
        if let context = todo.modelContext {
            do {
                try context.save()
            } catch {
                Self.logger.error("[\(#function)] Failed to save todo: \(error)")
            }
        }
    }

    func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let documentsDir = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first else { return }
            let attachmentsDir = documentsDir.appendingPathComponent("TodoAttachments", isDirectory: true)

            try? FileManager.default.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)

            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }

                let destURL = attachmentsDir.appendingPathComponent(url.lastPathComponent)
                do {
                    if FileManager.default.fileExists(atPath: destURL.path) {
                        try FileManager.default.removeItem(at: destURL)
                    }
                    try FileManager.default.copyItem(at: url, to: destURL)
                    todo.attachmentPaths.append(destURL.path)
                } catch {
                    Self.logger.error("[\(#function)] Failed to copy attachment: \(error)")
                }
            }

            if let context = todo.modelContext {
                do {
                    try context.save()
                } catch {
                    Self.logger.error("[\(#function)] Failed to save attachments: \(error)")
                }
            }
        case .failure(let error):
            Self.logger.error("[\(#function)] File import failed: \(error)")
        }
    }

    // MARK: - Work Item Creation

    func createWorkItemFromTodo() {
        guard let context = todo.modelContext else { return }

        // Create a new work model from this todo
        let work = WorkModel()
        work.title = todo.title
        work.setLegacyNoteText(todo.notes, in: context)
        work.dueAt = todo.dueDate

        // Assign to first student if available
        if let firstStudentID = todo.studentIDs.first {
            work.studentID = firstStudentID
        }

        context.insert(work)

        // Link the work to this todo
        todo.linkedWorkItemID = work.id.uuidString

        do {
            try context.save()
        } catch {
            Self.logger.error("[\(#function)] Failed to link work item: \(error)")
        }
    }

    // MARK: - Subtask Operations

    func addSubtask() {
        let newSubtask = TodoSubtask(
            title: "",
            orderIndex: (todo.subtasks ?? []).count
        )
        if todo.subtasks == nil { todo.subtasks = [] }
        todo.subtasks?.append(newSubtask)
        if let context = todo.modelContext {
            do {
                try context.save()
            } catch {
                Self.logger.error("[\(#function)] Failed to save subtask: \(error)")
            }
        }
    }

    func toggleSubtask(_ subtask: TodoSubtask) {
        subtask.isCompleted.toggle()
        if subtask.isCompleted {
            subtask.completedAt = Date()
        } else {
            subtask.completedAt = nil
        }
        if let context = todo.modelContext {
            do {
                try context.save()
            } catch {
                Self.logger.error("[\(#function)] Failed to toggle subtask: \(error)")
            }
        }
    }

    func deleteSubtask(_ subtask: TodoSubtask) {
        if let context = todo.modelContext {
            context.delete(subtask)
            do {
                try context.save()
            } catch {
                Self.logger.error("[\(#function)] Failed to delete subtask: \(error)")
            }
        }
    }

    func updateSubtask(_ subtask: TodoSubtask, title: String) {
        subtask.title = title
        if let context = todo.modelContext {
            do {
                try context.save()
            } catch {
                Self.logger.error("[\(#function)] Failed to update subtask: \(error)")
            }
        }
    }

    func reorderSubtasks(from source: IndexSet, to destination: Int) {
        var sorted = (todo.subtasks ?? []).sorted { $0.orderIndex < $1.orderIndex }
        sorted.move(fromOffsets: source, toOffset: destination)
        for (index, subtask) in sorted.enumerated() {
            subtask.orderIndex = index
        }
        if let context = todo.modelContext {
            do {
                try context.save()
            } catch {
                Self.logger.error("[\(#function)] Failed to reorder subtasks: \(error)")
            }
        }
    }

    // MARK: - Sharing & Templates

    // swiftlint:disable:next cyclomatic_complexity
    func formatTodoForSharing() -> String {
        var text = "📋 \(title.trimmed())\n"

        // Priority
        if priority != .none {
            let priorityEmoji = priority == .high ? "🔴" : priority == .medium ? "🟠" : "🔵"
            text += "\(priorityEmoji) Priority: \(priority.rawValue)\n"
        }

        // Due date
        if hasDueDate {
            text += "📅 Due: \(DateFormatters.mediumDate.string(from: dueDate))\n"
        }

        // Assigned students
        if !selectedStudentIDs.isEmpty {
            let assignedStudents = students.filter { selectedStudentIDs.contains($0.id.uuidString) }
            let names = assignedStudents.map(\.firstName).joined(separator: ", ")
            text += "👥 Assigned to: \(names)\n"
        }

        // Reminder
        if hasReminder {
            text += "🔔 Reminder: \(DateFormatters.mediumDateTime.string(from: reminderDate))\n"
        }

        // Time estimate
        let totalEstimated = estimatedHours * 60 + estimatedMinutes
        if totalEstimated > 0 {
            let hours = totalEstimated / 60
            let mins = totalEstimated % 60
            if hours > 0 && mins > 0 {
                text += "⏱️ Estimated time: \(hours)h \(mins)m\n"
            } else if hours > 0 {
                text += "⏱️ Estimated time: \(hours)h\n"
            } else {
                text += "⏱️ Estimated time: \(mins)m\n"
            }
        }

        // Mood
        if let mood = selectedMood {
            text += "\(mood.emoji) Mood: \(mood.rawValue)\n"
        }

        // Reflection
        let trimmedReflection = reflectionNotes.trimmed()
        if !trimmedReflection.isEmpty {
            text += "💭 Reflection: \(trimmedReflection)\n"
        }

        // Subtasks
        let detailSubs = todo.subtasks ?? []
        if !detailSubs.isEmpty {
            text += "\n✅ Subtasks (\(detailSubs.filter(\.isCompleted).count)/\(detailSubs.count)):\n"
            for subtask in detailSubs.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                let checkbox = subtask.isCompleted ? "☑️" : "☐"
                text += "  \(checkbox) \(subtask.title)\n"
            }
        }

        // Notes
        let trimmedNotes = notes.trimmed()
        if !trimmedNotes.isEmpty {
            text += "\n📝 Notes:\n\(trimmedNotes)\n"
        }

        return text
    }

    func saveAsTemplate() {
        guard !templateName.trimmed().isEmpty,
              let context = todo.modelContext else {
            templateName = ""
            return
        }

        let trimmedName = templateName.trimmed()
        let totalEstimated = estimatedHours * 60 + estimatedMinutes
        let selectedNames = students
            .filter { selectedStudentIDs.contains($0.id.uuidString) }
            .map(\.fullName)
        let syncedTemplateTags = TodoTagHelper.syncStudentTags(
            existingTags: todo.tags,
            studentNames: selectedNames
        )

        let template = TodoTemplate(
            name: trimmedName,
            title: title,
            notes: notes,
            priority: priority,
            defaultEstimatedMinutes: totalEstimated > 0 ? totalEstimated : nil,
            defaultStudentIDs: Array(selectedStudentIDs),
            tags: syncedTemplateTags
        )

        context.insert(template)
        do {
            try context.save()
        } catch {
            Self.logger.error("[\(#function)] Failed to save template: \(error)")
        }

        templateName = ""
    }

    // MARK: - Save & Close

    // swiftlint:disable:next function_body_length
    func save() {
        todo.title = title.trimmed()
        todo.notes = notes.trimmed()
        todo.studentIDs = Array(selectedStudentIDs)
        let selectedNames = students
            .filter { selectedStudentIDs.contains($0.id.uuidString) }
            .map(\.fullName)
        todo.tags = TodoTagHelper.syncStudentTags(
            existingTags: todo.tags,
            studentNames: selectedNames
        )
        todo.scheduledDate = scheduledDate
        todo.dueDate = deadlineDate
        todo.isSomeday = isSomeday
        todo.priority = priority
        todo.recurrence = recurrence
        todo.repeatAfterCompletion = recurrence != .none ? repeatAfterCompletion : false
        todo.customIntervalDays = recurrence == .custom ? customIntervalDays : nil

        // Save time estimates
        let totalEstimated = estimatedHours * 60 + estimatedMinutes
        let totalActual = actualHours * 60 + actualMinutes
        todo.estimatedMinutes = totalEstimated > 0 ? totalEstimated : nil
        todo.actualMinutes = totalActual > 0 ? totalActual : nil

        // Save mood and reflection
        todo.mood = selectedMood
        todo.reflectionNotes = reflectionNotes.trimmed()

        // Save location reminder
        if hasLocationReminder && !locationName.isEmpty {
            todo.locationName = locationName.trimmed()
            todo.notifyOnEntry = notifyOnEntry
            todo.notifyOnExit = notifyOnExit
            // Note: Actual coordinates would be set via location picker in full implementation
        } else {
            todo.locationName = nil
            todo.locationLatitude = nil
            todo.locationLongitude = nil
        }

        // Handle reminder notification
        Task {
            if hasReminder {
                isSchedulingNotification = true
                do {
                    try await TodoNotificationService.shared.scheduleNotification(for: todo, at: reminderDate)
                } catch {
                    Self.logger.error("Failed to schedule notification: \(error)")
                }
                isSchedulingNotification = false
            } else {
                // Cancel notification if reminder was disabled
                TodoNotificationService.shared.cancelNotification(for: todo)
            }

            if let context = todo.modelContext {
                do {
                    try context.save()
                } catch {
                    Self.logger.error("[\(#function)] Failed to save todo: \(error)")
                }
            }

            closeEditor()
        }
    }

    func closeEditor() {
        if let onDone {
            onDone()
        } else {
            dismiss()
        }
    }
}
