import Foundation
import Testing
@testable import CosmicDaybook

// Meeting drafts are one JSON blob per child. These pin the round trip, the
// cleanup of empty drafts, the move from the old ten-key drafts, and that the
// student record's Meetings tab (which leaves the workflow fields nil) can't
// wipe the workflow's checklist and reviews.
@Suite("Meeting draft store")
struct MeetingDraftStoreTests {
    private typealias Store = MeetingPersistenceService
    private typealias Draft = MeetingPersistenceService.CurrentMeetingData

    private func freshDefaults() -> UserDefaults {
        let name = "MeetingDraftStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("A draft round-trips through one key")
    func roundTrip() {
        let defaults = freshDefaults()
        let child = UUID()
        var draft = Draft()
        draft.reflectionText = "Proud of the timeline"
        draft.reviewedWorkIDs = [UUID().uuidString]
        draft.requestLessonIDs = [UUID().uuidString]
        Store.saveCurrent(studentID: child, data: draft, defaults: defaults)

        #expect(Store.loadCurrent(studentID: child, defaults: defaults) == draft)
        #expect(defaults.data(forKey: Store.draftKey(child)) != nil)
        #expect(Store.studentsWithDrafts(defaults: defaults) == [child])
    }

    @Test("Saving an empty draft removes the key instead of storing blanks")
    func emptyDraftRemovesKey() {
        let defaults = freshDefaults()
        let child = UUID()
        var draft = Draft()
        draft.reflectionText = "Something"
        Store.saveCurrent(studentID: child, data: draft, defaults: defaults)
        Store.saveCurrent(studentID: child, data: Draft(), defaults: defaults)

        #expect(defaults.object(forKey: Store.draftKey(child)) == nil)
        #expect(Store.studentsWithDrafts(defaults: defaults).isEmpty)
    }

    @Test("Clearing removes the draft")
    func clearRemovesDraft() {
        let defaults = freshDefaults()
        let child = UUID()
        var draft = Draft()
        draft.guideNotesText = "Private"
        Store.saveCurrent(studentID: child, data: draft, defaults: defaults)
        Store.clearCurrent(studentID: child, defaults: defaults)

        #expect(Store.loadCurrent(studentID: child, defaults: defaults) == Draft())
        #expect(defaults.object(forKey: Store.draftKey(child)) == nil)
    }

    @Test("A draft in the old per-field keys moves into the blob and the old keys go")
    func legacyDraftMigrates() {
        let defaults = freshDefaults()
        let child = UUID()
        let prefix = "StudentMeetings.current.\(child.uuidString)"
        defaults.set("Old reflection", forKey: prefix + ".reflection")
        defaults.set(["Choose a topic"], forKey: prefix + ".pendingFocusTexts")
        defaults.set("", forKey: prefix + ".guideNotes")

        #expect(Store.studentsWithDrafts(defaults: defaults) == [child])
        let draft = Store.loadCurrent(studentID: child, defaults: defaults)
        #expect(draft.reflectionText == "Old reflection")
        #expect(draft.pendingFocusTexts == ["Choose a topic"])
        #expect(defaults.object(forKey: prefix + ".reflection") == nil)
        #expect(defaults.object(forKey: prefix + ".guideNotes") == nil)
    }

    @Test("An old draft of nothing but empty keys is dropped, not migrated")
    func emptyLegacyDraftIsDropped() {
        let defaults = freshDefaults()
        let child = UUID()
        let prefix = "StudentMeetings.current.\(child.uuidString)"
        defaults.set("", forKey: prefix + ".reflection")
        defaults.set("", forKey: prefix + ".requests")

        #expect(Store.studentsWithDrafts(defaults: defaults).isEmpty)
        #expect(defaults.object(forKey: prefix + ".reflection") == nil)
    }

    @Test("A save that leaves the workflow fields nil keeps the stored ones")
    func nilWorkflowFieldsAreKept() {
        let defaults = freshDefaults()
        let child = UUID()
        let workID = UUID().uuidString
        var workflow = Draft()
        workflow.reviewedWorkIDs = [workID]
        workflow.pendingFocusTexts = ["Keep a journal"]
        Store.saveCurrent(studentID: child, data: workflow, defaults: defaults)

        var tab = Draft()
        tab.reflectionText = "Typed in the student record"
        Store.saveCurrent(studentID: child, data: tab, defaults: defaults)

        let stored = Store.loadCurrent(studentID: child, defaults: defaults)
        #expect(stored.reflectionText == "Typed in the student record")
        #expect(stored.reviewedWorkIDs == [workID])
        #expect(stored.pendingFocusTexts == ["Keep a journal"])
    }

    @Test("Ticking a focus item or reviewing work alone makes the meeting non-empty")
    func checklistAloneIsNotEmpty() {
        var resolved = Draft()
        resolved.resolvedFocusIDs = [UUID().uuidString]
        #expect(!resolved.isEmpty)

        var reviewed = Draft()
        reviewed.reviewedWorkIDs = [UUID().uuidString]
        #expect(!reviewed.isEmpty)

        #expect(Draft().isEmpty)
    }
}
