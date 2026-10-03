import Foundation
import Testing
@testable import CosmicDaybook

/// The plain-English wording feature screens show for their own errors
/// (Documentation/Implementation/PLAIN_ENGLISH_PLAN.md, Part 6). Each message
/// says what happened and what to do, with no raw system text.
@Suite("Feature screen messages")
@MainActor
struct FeatureScreenMessagesTests {

    @Test("A todo export is named in words, not a timestamp")
    func todoExportFileName() throws {
        let timeZone = try #require(TimeZone(identifier: "America/New_York"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 23)))

        let name = TodoExportService.exportFileName(
            on: date, locale: Locale(identifier: "en_US"), timeZone: timeZone
        )
        #expect(name == "Todos \u{2013} Oct 3, 2026")
    }

    @Test("A capture that can't be saved says nothing changed")
    func captureSaveErrors() {
        #expect(CaptureSaveError.saveFailed.errorDescription
                == "Couldn't save what you wrote. Nothing was changed. Try again.")
        #expect(CaptureSaveError.studentMissing.errorDescription
                == "One of these children is no longer in your class. Check the names and try again.")
        // A review-screen check is already plain and passes through as written.
        #expect(CaptureSaveError.invalid("Choose a lesson first.").errorDescription == "Choose a lesson first.")
    }

    @Test("A duplicate lesson name says where it is and what to do")
    func duplicateLessonName() {
        let error = LessonRepository.CreationError.duplicateName(
            existingID: nil, name: "The Rhombus", area: "Geometry", sequence: "Area"
        )
        #expect(error.errorDescription == "\"The Rhombus\" is already in Geometry › Area. Choose a different name.")
    }

    @Test("Story analysis failures stored on a story are plain sentences")
    func storyAnalyzerMessages() {
        #expect(StoryAnalyzerError.timedOut.errorDescription == "This took too long. Try again.")
        #expect(StoryAnalyzerError.unreadablePDF.errorDescription
                == "Couldn't open this PDF. Add the details yourself.")
        #expect(StoryAnalyzerError.aiUnavailable.errorDescription == AppleIntelligenceMessages.notAvailable)
    }

    @Test("Parsha suggestions with no album lessons say what to add")
    func parshaNoLessons() {
        #expect(ParshaSuggestionError.noAlbumLessons.errorDescription
                == "There are no album lessons yet. Add lessons from your albums, then try again.")
    }

    @Test("Lesson-planning progress reads in everyday words")
    func planningStepLabels() {
        #expect(PipelineStep.awaitingInput.displayLabel == "Your turn")
        #expect(PipelineStep.creatingAssignments.displayLabel == "Adding lessons to the plan…")
        #expect(PlanningError.studentNotFound.errorDescription
                == "Couldn't find this student. Close this and open it again.")
    }

    @Test("An unreadable model answer in the Parsha matcher gets the shared wording")
    func unreadableAnswerIsShared() {
        #expect(AppErrorMessages.aiMessage(for: LocalModelError.invalidJSON, fallback: "fallback")
                == LocalModelError.invalidJSON.errorDescription)
    }
}
