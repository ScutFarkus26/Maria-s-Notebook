import Foundation

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Meeting Summary Generator

/// Generates summaries for student meetings using AI or fallback logic.
enum MeetingSummaryGenerator {

    // MARK: - Fallback Summary

    /// Generates a fallback summary when AI is unavailable.
    static func generateFallbackSummary(for meeting: StudentMeeting) -> String {
        // For single-line display, prefer the most important field first
        let focusTrim = meeting.focus.trimmed()
        if !focusTrim.isEmpty {
            return focusTrim.count > 60 ? String(focusTrim.prefix(57)) + "..." : focusTrim
        }
        let reflTrim = meeting.reflection.trimmed()
        if !reflTrim.isEmpty {
            return reflTrim.count > 60 ? String(reflTrim.prefix(57)) + "..." : reflTrim
        }
        let reqTrim = meeting.requests.trimmed()
        if !reqTrim.isEmpty {
            return reqTrim.count > 60 ? String(reqTrim.prefix(57)) + "..." : reqTrim
        }
        let guideTrim = meeting.guideNotes.trimmed()
        if !guideTrim.isEmpty {
            return guideTrim.count > 60 ? String(guideTrim.prefix(57)) + "..." : guideTrim
        }
        return "Meeting"
    }

    // MARK: - AI Summary Generation

    /// Generates an AI summary for a meeting.
    ///
    /// - Parameters:
    ///   - meeting: The meeting to summarize
    ///   - onSummaryGenerated: Callback with the generated summary and whether it was AI-generated
    static func generateSummary(
        for meeting: StudentMeeting,
        onSummaryGenerated: @escaping @MainActor (String, Bool) -> Void
    ) async {
        let manualSummary = generateFallbackSummary(for: meeting)

        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        guard #available(macOS 26.0, *) else {
            await MainActor.run { onSummaryGenerated(manualSummary, false) }
            return
        }

        guard SystemLanguageModel.default.isAvailable else {
            await MainActor.run { onSummaryGenerated(manualSummary, false) }
            return
        }

        // Don't burn AI tokens if the content is very short
        let totalLength = meeting.reflection.count + meeting.guideNotes.count + meeting.focus.count + meeting.requests.count
        guard totalLength > 30 else {
            await MainActor.run { onSummaryGenerated(manualSummary, false) }
            return
        }

        let context = """
        Student Reflection: \(meeting.reflection)
        Focus: \(meeting.focus)
        Requests: \(meeting.requests)
        Guide Notes: \(meeting.guideNotes)
        """

        let instructions = "You are a Montessori guide assistant. Summarize this student meeting outcomes and sentiment in 2 sentences."
        let session = LanguageModelSession(instructions: instructions)

        do {
            let stream = session.streamResponse(
                to: "Summarize this meeting:\n\(context)",
                generating: MeetingSummary.self
            )

            var aiGenerated = false
            for try await partial in stream {
                if let overview = partial.content.overview, !overview.isEmpty {
                    await MainActor.run { onSummaryGenerated(overview, true) }
                    aiGenerated = true
                }
            }

            if !aiGenerated {
                await MainActor.run { onSummaryGenerated(manualSummary, false) }
            }
        } catch {
            #if DEBUG
            print("AI Summary failed: \(error)")
            #endif
            await MainActor.run { onSummaryGenerated(manualSummary, false) }
        }

        #else
        // Fallback: AI disabled
        await MainActor.run { onSummaryGenerated(manualSummary, false) }
        #endif
    }

    // MARK: - AI Availability

    /// Returns true if AI summary generation is available.
    static var isAIEnabled: Bool {
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }
}
