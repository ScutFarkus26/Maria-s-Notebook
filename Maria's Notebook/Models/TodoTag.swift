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

/// Helper for managing tags
struct TodoTagHelper {
    /// Common predefined tags
    static let commonTags = [
        ("Work", TagColor.blue),
        ("Personal", TagColor.purple),
        ("Urgent", TagColor.red),
        ("Meeting", TagColor.orange),
        ("Planning", TagColor.green),
        ("Research", TagColor.yellow),
        ("Review", TagColor.pink),
        ("Follow-up", TagColor.gray)
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
}
