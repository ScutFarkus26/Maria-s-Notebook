import CoreData
import Foundation
import os
import Testing
@testable import CosmicDaybook

/// What the calendar and community rows' restore does beyond their own
/// fields, since "Simplify round two", Phase 7 moved them onto row specs. The
/// spec oracle's golden attachment names no topic, and it doesn't watch for
/// notifications, so both are checked here:
///
/// - An attachment's `topicID` re-links it to its topic, restored before it:
///   to the topic the row names when it is here; a row naming one that isn't,
///   or none, leaves the link as it is (as the hand-written importer did).
/// - A restore that brings back days off or extra school days announces it
///   (`.schoolDayDataDidChange`), once for each of the two.
@Suite("Backup: community attachments' topics and the school calendar's announcement", .serialized)
@MainActor
struct BackupCalendarCommunityRestoreTests {

    /// A record of `type` from the fixture.
    private static func any<T: NSManagedObject>(_ type: T.Type, in context: NSManagedObjectContext) throws -> T {
        try #require(context.safeFetch(CDFetchRequest(type)).first, "the fixture holds a \(type)")
    }

    /// A store holding the field-coverage fixture, its attachment filed under
    /// its topic.
    private static func linkedFixture() throws -> (CoreDataStack, CDCommunityAttachment) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        try BackupFieldCoverageTests.seedEveryBackedUpEntity(into: context)
        let attachment = try any(CDCommunityAttachment.self, in: context)
        attachment.topic = try any(CDCommunityTopicEntity.self, in: context)
        #expect(CoreDataTestHelpers.save(context), "Fixture save failed")
        return (stack, attachment)
    }

    @Test("Through an archive into an empty notebook, the attachment comes back under its topic")
    func topicComesBack() async throws {
        let (source, attachment) = try Self.linkedFixture()
        let attachmentID = try #require(attachment.id)
        let topicID = try #require(attachment.topic?.id)

        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }
        try await BackupTestUtil.writeCurrentBackup(from: source.viewContext, to: url)
        // Merge into an empty notebook does what Replace would (BackupRoundTripTests).
        let restoredStack = try CoreDataTestHelpers.makeInMemoryStack()
        let restored = restoredStack.viewContext
        try await BackupTestUtil.importCurrentBackup(from: url, into: restored, mode: .merge)

        let restoredAttachment = try #require(
            try BackupTestUtil.fetchByID(
                CDCommunityAttachment.self, attachmentID, entityName: "CommunityAttachment", in: restored
            )
        )
        #expect(restoredAttachment.topic?.id == topicID)
    }

    @Test("A Merge files the attachment under the topic the row names, and leaves it when that isn't here")
    func mergeRelinksTheTopicTheRowNames() async throws {
        let (stack, attachment) = try Self.linkedFixture()
        let context = stack.viewContext
        let attachmentID = try #require(attachment.id)
        let other = CDCommunityTopicEntity(context: context)
        other.title = "Other topic"
        let otherID = try #require(other.id)
        #expect(CoreDataTestHelpers.save(context))
        #expect(attachment.topic?.id != otherID, "the fixture files it under another topic")

        /// A Merge of this notebook's backup with the attachment's `topicID` set to `topicID`.
        func restore(topicID: UUID?) async throws -> UUID? {
            var backup = Fix1102.payload(of: context)
            let row = try #require(backup.communityAttachments.firstIndex { $0.id == attachmentID })
            backup.communityAttachments[row].values["topicID"] = topicID.map(ModelValue.uuid)
            try await Fix1102.restore(backup, into: context, mode: .merge)
            let restored = try BackupTestUtil.fetchByID(
                CDCommunityAttachment.self, attachmentID, entityName: "CommunityAttachment", in: context
            )
            return restored?.topic?.id
        }

        #expect(try await restore(topicID: otherID) == otherID, "filed under the topic the row names")
        #expect(try await restore(topicID: UUID()) == otherID, "left as it is: the row's topic isn't here")
        #expect(try await restore(topicID: nil) == otherID, "left as it is: the row names no topic")
    }

    @Test("A restore bringing back a day off and an extra school day announces each")
    func schoolCalendarRestoreIsAnnounced() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let dayOff = CDNonSchoolDay(context: context)
        dayOff.date = Fix1102.at(0)
        let extraDay = CDSchoolDayOverride(context: context)
        extraDay.date = Fix1102.at(86_400)
        #expect(CoreDataTestHelpers.save(context))
        let backup = Fix1102.payload(of: context)
        #expect(backup.nonSchoolDays.count == 1 && backup.schoolDayOverrides.count == 1)

        let posts = OSAllocatedUnfairLock(initialState: 0)
        let center = NotificationCenter.default
        let token = center.addObserver(forName: .schoolDayDataDidChange, object: nil, queue: nil) { _ in
            posts.withLock { $0 += 1 }
        }
        defer { center.removeObserver(token) }

        let restoredStack = try CoreDataTestHelpers.makeInMemoryStack()
        try await Fix1102.restore(backup, into: restoredStack.viewContext, mode: .merge)
        // Nothing else in a restore into an in-memory store posts it.
        #expect(posts.withLock { $0 } >= 2, "one for the days off, one for the extra school days")
    }
}
