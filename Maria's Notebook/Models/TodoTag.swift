import Foundation
import SwiftUI

/// Predefined tag colors for visual organization
enum TagColor: String, Codable, CaseIterable {
    case red = "Red"
    case orange = "Orange"
    case yellow = "Yellow"
    case green = "Green"
    case blue = "Blue"
    case purple = "Purple"
    case pink = "Pink"
    case gray = "Gray"
    
    var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .gray: return .gray
        }
    }
    
    var lightColor: Color {
        color.opacity(0.2)
    }
}

/// Backward-compatible alias
typealias TodoTagHelper = TagHelper

/// Helper for managing tags
struct TagHelper {
    static let studentTagParent = "Students"

    /// Common predefined tags
    static let commonTags = [
        ("Work", TagColor.blue),
        ("Personal", TagColor.purple),
        ("Urgent", TagColor.red),
        ("Meeting", TagColor.orange),
        ("Planning", TagColor.green),
        ("Research", TagColor.yellow),
        ("Review", TagColor.pink),
        ("Follow-up", TagColor.gray),
        ("Student", TagColor.green),
        ("Administrative", TagColor.orange),
        ("Lesson Planning", TagColor.blue),
        ("Grading", TagColor.orange),
        ("Communication", TagColor.green),
        ("Professional Development", TagColor.pink)
    ]
    
    /// Extract color from tag string (format: "tagName|colorRaw")
    static func parseTag(_ tag: String) -> (name: String, color: TagColor) {
        let components = tag.split(separator: "|")
        if components.count == 2,
           let colorRaw = components.last,
           let color = TagColor(rawValue: String(colorRaw)) {
            return (String(components[0]), color)
        }
        return (tag, .gray)
    }
    
    /// Create tag string from name and color
    static func createTag(name: String, color: TagColor) -> String {
        return "\(name)|\(color.rawValue)"
    }
    
    /// Get just the display name from a tag
    static func tagName(_ tag: String) -> String {
        return parseTag(tag).name
    }
    
    /// Get color for a tag
    static func tagColor(_ tag: String) -> TagColor {
        return parseTag(tag).color
    }

    static func tagPathComponents(_ tag: String) -> [String] {
        tagName(tag)
            .split(separator: "/")
            .map(String.init)
    }

    static func rootTagName(_ tag: String) -> String {
        tagPathComponents(tag).first ?? tagName(tag)
    }

    static func leafTagName(_ tag: String) -> String {
        tagPathComponents(tag).last ?? tagName(tag)
    }

    static func isStudentTag(_ tag: String) -> Bool {
        rootTagName(tag).localizedCaseInsensitiveCompare(studentTagParent) == .orderedSame
    }

    static func createStudentTag(name: String, color: TagColor = .green) -> String {
        createTag(name: "\(studentTagParent)/\(name)", color: color)
    }

    static func syncStudentTags(
        existingTags: [String],
        studentNames: [String],
        color: TagColor = .green
    ) -> [String] {
        var synced = existingTags.filter { !isStudentTag($0) }
        let existingNames = Set(synced.map { tagName($0).lowercased() })
        var mutableExistingNames = existingNames

        for studentName in studentNames {
            let trimmed = studentName.trimmed()
            guard !trimmed.isEmpty else { continue }

            let studentTag = createStudentTag(name: trimmed, color: color)
            let normalized = tagName(studentTag).lowercased()
            guard !mutableExistingNames.contains(normalized) else { continue }
            synced.append(studentTag)
            mutableExistingNames.insert(normalized)
        }

        return synced
    }

    // MARK: - Note Category Migration Helpers

    /// Maps old NoteCategory raw values to TagColor for migration
    static func colorForNoteCategory(_ categoryRaw: String) -> TagColor {
        switch categoryRaw {
        case "academic": return .blue
        case "behavioral": return .orange
        case "social": return .purple
        case "emotional": return .pink
        case "health": return .red
        case "attendance": return .green
        case "general": return .gray
        default: return .gray
        }
    }

    /// Creates a tag string from an old NoteCategory raw value
    static func tagFromNoteCategory(_ categoryRaw: String) -> String {
        let name = categoryRaw.prefix(1).uppercased() + categoryRaw.dropFirst()
        let color = colorForNoteCategory(categoryRaw)
        return createTag(name: name, color: color)
    }
}
