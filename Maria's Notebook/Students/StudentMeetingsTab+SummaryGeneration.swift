// StudentMeetingsTab+SummaryGeneration.swift
// AI summary generation for meeting history

import SwiftUI
import CoreData

extension StudentMeetingsTab {

    // MARK: - Summary Generation (delegated to MeetingSummaryGenerator)

    var isAIEnabled: Bool {
        MeetingSummaryGenerator.isAIEnabled
    }

    func summaryText(for item: CDStudentMeeting) -> String {
        MeetingSummaryGenerator.generateFallbackSummary(for: item)
    }

    func generateSummary(for item: CDStudentMeeting) async {
        guard let itemID = item.id else { return }
        generatingSummaries.insert(itemID)

        await MeetingSummaryGenerator.generateSummary(for: item) { text, isAI in
            setSummary(text, for: itemID, isAIGenerated: isAI)
        }

        generatingSummaries.remove(itemID)
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
