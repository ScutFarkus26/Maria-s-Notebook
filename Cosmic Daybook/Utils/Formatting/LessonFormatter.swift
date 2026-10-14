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
    
    /// Returns a fallback title if the name is empty.
    /// - Parameters:
    ///   - name: The lesson name
    ///   - fallback: The fallback title (default: "Untitled Lesson")
    /// - Returns: The name if not empty, otherwise the fallback
    nonisolated static func titleOrFallback(_ name: String, fallback: String = "Untitled Lesson") -> String {
        StringFallbacks.trimmedValueOrFallback(name, fallback: fallback)
    }

    /// What a work row says when its lesson has no name on file.
    nonisolated static let untitledWork = "Untitled work"
    /// What a presentation says when its lesson has no name on file.
    nonisolated static let untitledLesson = "Untitled lesson"

    /// The name a work or presentation row shows for its lesson: the
    /// lesson's own name; else the title the row keeps for itself (a work's
    /// title, a presentation's lesson snapshot); else `missing`, a plain
    /// phrase. Never the lesson's id: a few id characters mean nothing to
    /// the guide (plain English on screen, 2026-10-14 review).
    nonisolated static func lessonName(
        _ name: String?, orRowTitle rowTitle: String? = nil, missing: String
    ) -> String {
        for candidate in [name, rowTitle] {
            let trimmed = candidate?.trimmed() ?? ""
            if !trimmed.isEmpty { return trimmed }
        }
        return missing
    }
}
