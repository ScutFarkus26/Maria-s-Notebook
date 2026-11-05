import CoreData
import CoreGraphics
import Foundation
import Testing
@testable import CosmicDaybook

/// What a restore does with an issue's actions, a going-out's checklist,
/// a planning recommendation and an album's highlights and ink, since
/// "Simplify round two", Phase 7 moved their rows onto row specs. The spec
/// oracle restores the golden row into a store already holding the same
/// values, and its golden rows only ever name a parent that is there, so a
/// link to another parent, a rule between two keys or a row passed over
/// doesn't show there:
///
/// - An action is filed under the issue its row names when that is here; one
///   naming an issue that isn't, or no id at all, keeps its link.
/// - A checklist line whose `goingOutID` isn't an id is passed over; one that
///   is restores it upper-cased and files the line under that going-out.
/// - An issue's children and an action's participants restore without dating
///   the record now (their typed setters stamp `updatedAt`).
/// - A recommendation restores only with its lesson and session ids and a
///   planning depth; its children come back as the ids that parse,
///   upper-cased, and a row without them as an empty list.
/// - A highlight's rectangles restore four numbers each; a page without ink
///   goes out with empty data, which restores as no drawing.
///
/// A to-do done here stays done against the backup (`ModelRow`'s
/// `rowCompletedAt`): `BackupMergeReviewFixTests`.
@Suite("Backup: issue actions, checklists, recommendations and album marks", .serialized)
@MainActor
struct BackupIssuePlanningAlbumRestoreTests {

    /// A Merge of the notebook's own backup, with `change` made to the row
    /// of `id` in `field`.
    private static func restore<Kind: ModelRowKind>(
        _ field: WritableKeyPath<BackupPayload, [ModelRow<Kind>]?>,
        id: UUID,
        in context: NSManagedObjectContext,
        _ change: (inout [String: ModelValue]) -> Void
    ) async throws {
        var backup = Fix1102.payload(of: context)
        var rows = try #require(backup[keyPath: field])
        let index = try #require(rows.firstIndex { $0.id == id })
        change(&rows[index].values)
        backup[keyPath: field] = rows
        try await Fix1102.restore(backup, into: context, mode: .merge)
    }

    private static func fetch<T: NSManagedObject>(
        _ type: T.Type, _ id: UUID, _ entityName: String, in context: NSManagedObjectContext
    ) throws -> T {
        try #require(try BackupTestUtil.fetchByID(type, id, entityName: entityName, in: context))
    }

    @Test("A Merge files an action under the issue its row names, and leaves it when that isn't here")
    func mergeRelinksTheActionsIssue() async throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let first = CDIssue(context: context)
        let other = CDIssue(context: context)
        let action = CDIssueAction(context: context)
        action.issue = first
        action.issueID = try #require(first.id).uuidString
        let actionID = try #require(action.id)
        let otherID = try #require(other.id)
        #expect(CoreDataTestHelpers.save(context))

        /// The action's issue and `issueID` after a Merge whose row names `issueID`.
        func restore(issueID: String) async throws -> (issue: UUID?, issueID: String) {
            try await Self.restore(\.issueActions, id: actionID, in: context) { $0["issueID"] = .string(issueID) }
            let back = try Self.fetch(CDIssueAction.self, actionID, "IssueAction", in: context)
            return (back.issue?.id, back.issueID)
        }

        let named = try await restore(issueID: otherID.uuidString)
        #expect(named.issue == otherID && named.issueID == otherID.uuidString, "filed under the issue the row names")
        let missing = UUID().uuidString
        let notHere = try await restore(issueID: missing)
        #expect(notHere.issue == otherID, "left as it is: the row's issue isn't here")
        #expect(notHere.issueID == missing, "the row's id restores as it is")
        let notAnID = try await restore(issueID: "not an id")
        #expect(notAnID.issue == otherID && notAnID.issueID == "not an id", "restored, its link left as it is")
    }

    @Test("A checklist line whose going-out isn't an id is passed over; one that is restores upper-cased, under it")
    func checklistLineFollowsItsGoingOut() async throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let first = CDGoingOut(context: context)
        let other = CDGoingOut(context: context)
        let item = CDGoingOutChecklistItem(context: context)
        item.title = "Pack lunches"
        item.goingOut = first
        item.goingOutID = try #require(first.id).uuidString
        let itemID = try #require(item.id)
        let otherID = try #require(other.id)
        #expect(CoreDataTestHelpers.save(context))

        try await Self.restore(\.goingOutChecklistItems, id: itemID, in: context) {
            $0["goingOutID"] = .string(otherID.uuidString.lowercased())
        }
        var back = try Self.fetch(CDGoingOutChecklistItem.self, itemID, "GoingOutChecklistItem", in: context)
        #expect(back.goingOut?.id == otherID, "filed under the going-out the row names")
        #expect(back.goingOutID == otherID.uuidString, "its id restores upper-cased")

        try await Self.restore(\.goingOutChecklistItems, id: itemID, in: context) {
            $0["goingOutID"] = .string("not an id")
            $0["title"] = .string("Pack snacks")
        }
        back = try Self.fetch(CDGoingOutChecklistItem.self, itemID, "GoingOutChecklistItem", in: context)
        #expect(back.title == "Pack lunches", "passed over: the line keeps its own")
        #expect(back.goingOutID == otherID.uuidString && back.goingOut?.id == otherID)
    }

    @Test("An issue's children and an action's participants restore without dating the record now")
    func childrenKeepTheRowsUpdatedDate() async throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let issue = CDIssue(context: context)
        let action = CDIssueAction(context: context)
        issue.studentIDs = [UUID().uuidString]
        action.participantStudentIDs = [UUID().uuidString]
        issue.updatedAt = Fix1102.at(10)
        action.updatedAt = Fix1102.at(10)
        let issueID = try #require(issue.id)
        let actionID = try #require(action.id)
        #expect(CoreDataTestHelpers.save(context))

        let child = UUID().uuidString
        try await Self.restore(\.issues, id: issueID, in: context) {
            $0["studentIDs"] = .strings([child])
            $0["updatedAt"] = .date(Fix1102.at(20))
        }
        try await Self.restore(\.issueActions, id: actionID, in: context) {
            $0["participantStudentIDs"] = .strings([child])
            $0["updatedAt"] = .date(Fix1102.at(20))
        }
        let issueBack = try Self.fetch(CDIssue.self, issueID, "Issue", in: context)
        let actionBack = try Self.fetch(CDIssueAction.self, actionID, "IssueAction", in: context)
        #expect(issueBack.studentIDs == [child])
        #expect(issueBack.updatedAt == Fix1102.at(20), "the row's date, not the moment of the restore")
        #expect(actionBack.participantStudentIDs == [child])
        #expect(actionBack.updatedAt == Fix1102.at(20), "the row's date, not the moment of the restore")
    }

    @Test("A recommendation restores only with its ids and a planning depth, its children upper-cased")
    func recommendationRules() async throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let recommendation = CDPlanningRecommendation(context: context)
        recommendation.lessonID = UUID().uuidString
        recommendation.planningSessionID = UUID().uuidString
        recommendation.depthLevel = PlanningDepth.standard.rawValue
        recommendation.reasoning = "Ready for the next lesson"
        recommendation.studentIDs = [UUID().uuidString]
        let id = try #require(recommendation.id)
        #expect(CoreDataTestHelpers.save(context))
        let back = { try Self.fetch(CDPlanningRecommendation.self, id, "PlanningRecommendation", in: context) }

        let child = UUID()
        let lesson = UUID()
        try await Self.restore(\.planningRecommendations, id: id, in: context) {
            let blob = CloudKitStringArrayStorage.encode([child.uuidString.lowercased(), "not an id"])
            $0["studentIDsData"] = blob.map(ModelValue.data)
            $0["lessonID"] = .string(lesson.uuidString.lowercased())
        }
        #expect(try back().studentIDs == [child.uuidString], "the children that are ids, upper-cased")
        #expect(try back().lessonID == lesson.uuidString, "the lesson's id upper-cased")

        try await Self.restore(\.planningRecommendations, id: id, in: context) { $0["studentIDsData"] = nil }
        #expect(try back().studentIDs.isEmpty)
        #expect(try back()._studentIDsData != nil, "a row without children restores an empty list, not none")

        for (key, value) in [("depthLevel", "deepest"), ("lessonID", "not an id"), ("planningSessionID", "nope")] {
            try await Self.restore(\.planningRecommendations, id: id, in: context) {
                $0[key] = .string(value)
                $0["reasoning"] = .string("Changed")
            }
            #expect(try back().reasoning == "Ready for the next lesson", "passed over: \(key) is \(value)")
        }
    }

    @Test("A highlight's rectangles restore four numbers each; a page without ink goes out empty and restores as none")
    func albumMarks() async throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let highlight = CDAlbumHighlight(context: context)
        highlight.albumID = "album-1"
        highlight.rects = [CGRect(x: 1, y: 2, width: 3, height: 4)]
        let ink = CDAlbumPageInk(context: context)
        ink.albumID = "album-1"
        ink.drawingData = Data([1, 2, 3])
        let blank = CDAlbumPageInk(context: context)
        let highlightID = try #require(highlight.id)
        let inkID = try #require(ink.id)
        let blankID = try #require(blank.id)
        #expect(CoreDataTestHelpers.save(context))

        let backup = Fix1102.payload(of: context)
        let highlightRow = backup.albumHighlights?.first { $0.id == highlightID }
        #expect(highlightRow?.values["rects"] == .doubleArrays([[1, 2, 3, 4]]), "the rectangles as plain numbers")
        let blankRow = backup.albumPageInk?.first { $0.id == blankID }
        #expect(blankRow?.values["drawingData"] == .data(Data()), "a page without ink goes out with empty data")

        try await Self.restore(\.albumHighlights, id: highlightID, in: context) {
            $0["rects"] = .doubleArrays([[5, 6, 7, 8], [9, 10]])
        }
        let highlightBack = try Self.fetch(CDAlbumHighlight.self, highlightID, "AlbumHighlight", in: context)
        #expect(highlightBack.rectValues == [[5, 6, 7, 8]], "a rectangle that isn't four numbers is dropped")

        try await Self.restore(\.albumPageInk, id: inkID, in: context) { $0["drawingData"] = .data(Data()) }
        let inkBack = try Self.fetch(CDAlbumPageInk.self, inkID, "AlbumPageInk", in: context)
        #expect(inkBack.drawingData == nil, "empty ink restores as no drawing")
    }
}
