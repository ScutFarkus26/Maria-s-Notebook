import Foundation

/// Centralized formatting utilities for lesson display titles and related strings.
/// Consolidates lesson formatting logic used across the app.
/// All methods are nonisolated to allow calling from any actor context.
enum LessonFormatter {
    /// Formats a lesson title with optional area and sequence.
    /// - Parameters:
    ///   - name: The lesson name
    ///   - area: Optional area
    ///   - sequence: Optional sequence
    /// - Returns: Formatted lesson title string
    nonisolated static func displayTitle(name: String, area: String? = nil, sequence: String? = nil) -> String {
        let trimmedName = name.trimmed()
        let trimmedArea = area?.trimmed() ?? ""
        let trimmedSequence = sequence?.trimmed() ?? ""
        
        var suffix = ""
        if !trimmedArea.isEmpty && !trimmedSequence.isEmpty {
            suffix = " • \(trimmedArea) • \(trimmedSequence)"
        } else if !trimmedArea.isEmpty {
            suffix = " • \(trimmedArea)"
        } else if !trimmedSequence.isEmpty {
            suffix = " • \(trimmedSequence)"
        }
        
        return trimmedName + suffix
    }
    
    /// Formats a lesson title for duplicate detection display.
    /// - Parameters:
    ///   - name: The lesson name
    ///   - area: The area
    ///   - sequence: Optional sequence
    /// - Returns: Formatted duplicate detection title
    nonisolated static func duplicateDetectionTitle(name: String, area: String, sequence: String) -> String {
        let trimmedSequence = sequence.trimmed()
        return trimmedSequence.isEmpty 
            ? "\(name) — \(area)" 
            : "\(name) — \(area) • \(trimmedSequence)"
    }
    
    /// Returns a fallback title if the name is empty.
    /// - Parameters:
    ///   - name: The lesson name
    ///   - fallback: The fallback title (default: "Untitled Lesson")
    /// - Returns: The name if not empty, otherwise the fallback
    nonisolated static func titleOrFallback(_ name: String, fallback: String = "Untitled Lesson") -> String {
        StringFallbacks.trimmedValueOrFallback(name, fallback: fallback)
    }
}
