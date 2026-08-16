import Foundation
import Testing
@testable import Maria_s_Notebook

@Suite("Presentation Follow-Up Work Drafts")
@MainActor
struct PresentationFollowUpWorkDraftStoreTests {
    @Test("Unfinished text is restored for the same presentation and child scope")
    func scopedDraftRoundTrip() throws {
        let suite = "PresentationFollowUpWorkDraftStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let presentationID = UUID()
        let firstStudentID = UUID().uuidString
        let secondStudentID = UUID().uuidString

        PresentationFollowUpWorkDraftStore.save(
            presentationID: presentationID,
            studentIDs: [firstStudentID],
            title: "Biography on Stan Lee",
            kind: .research,
            sampleWorkID: nil,
            defaults: defaults
        )

        let restored = try #require(PresentationFollowUpWorkDraftStore.load(
            presentationID: presentationID,
            studentIDs: [firstStudentID],
            defaults: defaults
        ))
        #expect(restored.title == "Biography on Stan Lee")
        #expect(restored.kind == .research)
        #expect(PresentationFollowUpWorkDraftStore.load(
            presentationID: presentationID,
            studentIDs: [secondStudentID],
            defaults: defaults
        ) == nil)
    }

    @Test("Saving an empty title clears only that scope")
    func emptyTitleClearsDraft() throws {
        let suite = "PresentationFollowUpWorkDraftStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let presentationID = UUID()
        let studentID = UUID().uuidString

        PresentationFollowUpWorkDraftStore.save(
            presentationID: presentationID,
            studentIDs: [studentID],
            title: "Symbolize four sentences",
            kind: .followUpAssignment,
            sampleWorkID: nil,
            defaults: defaults
        )
        PresentationFollowUpWorkDraftStore.save(
            presentationID: presentationID,
            studentIDs: [studentID],
            title: "   ",
            kind: .followUpAssignment,
            sampleWorkID: nil,
            defaults: defaults
        )

        #expect(PresentationFollowUpWorkDraftStore.load(
            presentationID: presentationID,
            studentIDs: [studentID],
            defaults: defaults
        ) == nil)
    }
}
