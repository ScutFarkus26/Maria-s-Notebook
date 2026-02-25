import Foundation
import SwiftData
import OSLog
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Service for exporting todos to various formats
@MainActor
class TodoExportService {
    private static let logger = Logger.todos

    // MARK: - Export Formats
    
    enum ExportFormat {
        case text
        case csv
        case markdown
        case json
    }
    
    // MARK: - Text Export
    
    static func exportAsText(todos: [TodoItem]) -> String {
        var output = "TODO LIST EXPORT\n"
        output += "===============\n"
        output += "Exported: \(Date().formatted(date: .long, time: .shortened))\n"
        output += "Total tasks: \(todos.count)\n\n"
        
        for (index, todo) in todos.enumerated() {
            output += "[\(index + 1)] \(todo.isCompleted ? "✓" : "○") \(todo.title)\n"
            
            if !todo.notes.isEmpty {
                output += "    Notes: \(todo.notes)\n"
            }
            
            if todo.priority != .none {
                output += "    Priority: \(todo.priority.rawValue)\n"
            }
            
            if let scheduled = todo.scheduledDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                output += "    Scheduled: \(formatter.string(from: scheduled))\n"
            }
            if let dueDate = todo.dueDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                output += "    Deadline: \(formatter.string(from: dueDate))\n"
            }
            if todo.isSomeday {
                output += "    Status: Someday\n"
            }
            
            if let mood = todo.mood {
                output += "    Mood: \(mood.emoji) \(mood.rawValue)\n"
            }
            
            if !todo.reflectionNotes.isEmpty {
                output += "    Reflection: \(todo.reflectionNotes)\n"
            }
            
            if !todo.subtasks.isEmpty {
                output += "    Subtasks (\(todo.subtasks.filter { $0.isCompleted }.count)/\(todo.subtasks.count)):\n"
                for subtask in todo.subtasks.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                    output += "      \(subtask.isCompleted ? "✓" : "○") \(subtask.title)\n"
                }
            }
            
            output += "\n"
        }
        
        return output
    }
    
    // MARK: - CSV Export
    
    static func exportAsCSV(todos: [TodoItem]) -> String {
        var output = "Title,Status,Priority,Tags,Scheduled Date,Deadline,Created,Notes,Mood,Subtasks Completed,Subtasks Total\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        
        for todo in todos {
            let title = escapeCSV(todo.title)
            let status: String
            if todo.isSomeday {
                status = "Someday"
            } else {
                status = todo.isCompleted ? "Completed" : "Active"
            }
            let priority = todo.priority.rawValue
            let tags = escapeCSV(todo.tags.map { TodoTagHelper.tagName($0) }.joined(separator: "; "))
            let scheduledDate = todo.scheduledDate.map { dateFormatter.string(from: $0) } ?? ""
            let deadline = todo.dueDate.map { dateFormatter.string(from: $0) } ?? ""
            let created = dateFormatter.string(from: todo.createdAt)
            let notes = escapeCSV(todo.notes)
            let mood = todo.mood?.rawValue ?? ""
            let subtasksCompleted = todo.subtasks.filter { $0.isCompleted }.count
            let subtasksTotal = todo.subtasks.count
            
            output += "\(title),\(status),\(priority),\(tags),\(scheduledDate),\(deadline),\(created),\(notes),\(mood),\(subtasksCompleted),\(subtasksTotal)\n"
        }
        
        return output
    }
    
    private static func escapeCSV(_ string: String) -> String {
        if string.contains(",") || string.contains("\"") || string.contains("\n") {
            return "\"\(string.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return string
    }
    
    // MARK: - Markdown Export
    
    static func exportAsMarkdown(todos: [TodoItem]) -> String {
        var output = "# Todo List Export\n\n"
        output += "*Exported: \(Date().formatted(date: .long, time: .shortened))*\n\n"
        output += "**Total tasks:** \(todos.count)\n\n"
        output += "---\n\n"
        
        for todo in todos {
            output += "### \(todo.isCompleted ? "~~\(todo.title)~~" : todo.title)\n\n"
            
            var metadata: [String] = []
            if todo.priority != .none {
                metadata.append("**Priority:** \(todo.priority.rawValue)")
            }
            if let scheduled = todo.scheduledDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                metadata.append("**Scheduled:** \(formatter.string(from: scheduled))")
            }
            if let dueDate = todo.dueDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                metadata.append("**Deadline:** \(formatter.string(from: dueDate))")
            }
            if todo.isSomeday {
                metadata.append("**Someday**")
            }
            if let mood = todo.mood {
                metadata.append("**Mood:** \(mood.emoji) \(mood.rawValue)")
            }
            if !todo.tags.isEmpty {
                let tagNames = todo.tags.map { TodoTagHelper.tagName($0) }.joined(separator: ", ")
                metadata.append("**Tags:** \(tagNames)")
            }
            
            if !metadata.isEmpty {
                output += metadata.joined(separator: " | ") + "\n\n"
            }
            
            if !todo.notes.isEmpty {
                output += "> \(todo.notes)\n\n"
            }
            
            if !todo.subtasks.isEmpty {
                output += "**Subtasks:**\n\n"
                for subtask in todo.subtasks.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                    output += "- [\(subtask.isCompleted ? "x" : " ")] \(subtask.title)\n"
                }
                output += "\n"
            }
            
            if !todo.reflectionNotes.isEmpty {
                output += "**Reflection:** \(todo.reflectionNotes)\n\n"
            }
            
            output += "---\n\n"
        }
        
        return output
    }
    
    // MARK: - JSON Export
    
    static func exportAsJSON(todos: [TodoItem]) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let exportData = todos.map { todo -> [String: Any] in
            var dict: [String: Any] = [
                "id": todo.id.uuidString,
                "title": todo.title,
                "isCompleted": todo.isCompleted,
                "createdAt": ISO8601DateFormatter().string(from: todo.createdAt),
                "priority": todo.priority.rawValue,
                "tags": todo.tags.map { TodoTagHelper.tagName($0) }
            ]
            
            if !todo.notes.isEmpty {
                dict["notes"] = todo.notes
            }
            
            if let scheduled = todo.scheduledDate {
                dict["scheduledDate"] = ISO8601DateFormatter().string(from: scheduled)
            }
            if let dueDate = todo.dueDate {
                dict["deadline"] = ISO8601DateFormatter().string(from: dueDate)
            }
            if todo.isSomeday {
                dict["isSomeday"] = true
            }
            
            if let mood = todo.mood {
                dict["mood"] = mood.rawValue
            }
            
            if !todo.reflectionNotes.isEmpty {
                dict["reflectionNotes"] = todo.reflectionNotes
            }
            
            if !todo.subtasks.isEmpty {
                dict["subtasks"] = todo.subtasks.map { subtask in
                    [
                        "title": subtask.title,
                        "isCompleted": subtask.isCompleted,
                        "orderIndex": subtask.orderIndex
                    ]
                }
            }
            
            return dict
        }
        
        let jsonData: Data
        do {
            jsonData = try JSONSerialization.data(withJSONObject: exportData, options: [.prettyPrinted, .sortedKeys])
        } catch {
            Self.logger.warning("Failed to serialize JSON: \(error, privacy: .public)")
            return nil
        }
        
        return String(data: jsonData, encoding: .utf8)
    }
    
    // MARK: - File Saving
    
    static func saveToFile(content: String, filename: String, format: ExportFormat) -> URL? {
        let fileExtension: String
        switch format {
        case .text: fileExtension = "txt"
        case .csv: fileExtension = "csv"
        case .markdown: fileExtension = "md"
        case .json: fileExtension = "json"
        }
        
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
            .appendingPathExtension(fileExtension)
        
        do {
            try content.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            Self.logger.warning("Failed to save file: \(error, privacy: .public)")
            return nil
        }
    }
}
