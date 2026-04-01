import Foundation

/// Centralized formatting utilities for lesson display titles and related strings.
/// Consolidates lesson formatting logic used across the app.
/// All methods are nonisolated to allow calling from any actor context.
enum LessonFormatter {
    /// Formats a lesson title with optional subject and group.
    /// - Parameters:
    ///   - name: The lesson name
    ///   - subject: Optional subject
    ///   - group: Optional group
    /// - Returns: Formatted lesson title string
    nonisolated static func displayTitle(name: String, subject: String? = nil, group: String? = nil) -> String {
        let trimmedName = name.trimmed()
        let trimmedSubject = subject?.trimmed() ?? ""
        let trimmedGroup = group?.trimmed() ?? ""
        
        var suffix = ""
        if !trimmedSubject.isEmpty && !trimmedGroup.isEmpty {
            suffix = " • \(trimmedSubject) • \(trimmedGroup)"
        } else if !trimmedSubject.isEmpty {
            suffix = " • \(trimmedSubject)"
        } else if !trimmedGroup.isEmpty {
            suffix = " • \(trimmedGroup)"
        }
        
        return trimmedName + suffix
    }
    
    /// Formats a lesson title for duplicate detection display.
    /// - Parameters:
    ///   - name: The lesson name
    ///   - subject: The subject
    ///   - group: Optional group
    /// - Returns: Formatted duplicate detection title
    nonisolated static func duplicateDetectionTitle(name: String, subject: String, group: String) -> String {
        let trimmedGroup = group.trimmed()
        return trimmedGroup.isEmpty 
            ? "\(name) — \(subject)" 
            : "\(name) — \(subject) • \(trimmedGroup)"
    }
    
    /// Returns a fallback title if the name is empty.
    /// - Parameters:
    ///   - name: The lesson name
    ///   - fallback: The fallback title (default: "Untitled CDLesson")
    /// - Returns: The name if not empty, otherwise the fallback
    nonisolated static func titleOrFallback(_ name: String, fallback: String = "Untitled CDLesson") -> String {
        StringFallbacks.trimmedValueOrFallback(name, fallback: fallback)
    }
}
