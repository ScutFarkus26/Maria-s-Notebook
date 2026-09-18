import Foundation

/// Lifecycle of AI metadata extraction for a `CDStory`.
public enum StoryAnalysisStatus: String, Sendable {
    /// Newly imported, queued for analysis.
    case pending
    /// Currently in the analysis queue or running.
    case analyzing
    /// AI analysis completed successfully.
    case complete
    /// AI analysis failed; user can re-trigger.
    case failed
    /// AI is unavailable or the PDF had no extractable text — user fills metadata in by hand.
    case manual
    /// PDF was replaced after analysis; metadata may be out of date.
    case stale
}
