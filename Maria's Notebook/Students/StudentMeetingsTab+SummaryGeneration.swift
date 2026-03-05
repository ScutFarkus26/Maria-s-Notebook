// StudentMeetingsTab+SummaryGeneration.swift
// AI summary generation for meeting history

import SwiftUI

extension StudentMeetingsTab {

    // MARK: - Summary Generation (delegated to MeetingSummaryGenerator)

    var isAIEnabled: Bool {
        MeetingSummaryGenerator.isAIEnabled
    }

    func summaryText(for item: StudentMeeting) -> String {
        MeetingSummaryGenerator.generateFallbackSummary(for: item)
    }

    func generateSummary(for item: StudentMeeting) async {
        generatingSummaries.insert(item.id)

        await MeetingSummaryGenerator.generateSummary(for: item) { [item] text, isAI in
            setSummary(text, for: item.id, isAIGenerated: isAI)
        }

        generatingSummaries.remove(item.id)
    }

    @MainActor
    func setSummary(_ text: String, for meetingID: UUID, isAIGenerated: Bool = false) {
        meetingSummaries[meetingID] = text
        if isAIGenerated {
            aiGeneratedSummaries.insert(meetingID)
        } else {
            aiGeneratedSummaries.remove(meetingID)
        }
    }
}
