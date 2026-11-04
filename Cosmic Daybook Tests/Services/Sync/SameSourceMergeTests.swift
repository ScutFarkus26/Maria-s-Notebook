import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// The merges for rows that stand for one thing under two ids — a reset
/// device's EventKit mirror and template seed racing the iCloud download
/// (see `DataCleanupService+SameSourceMerges`).
@Suite("Same-source merges")
@MainActor
struct SameSourceMergeTests {

    private let early = Date(timeIntervalSince1970: 1_780_000_000)
    private let late = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: - Calendar events

    @Test("Events fold on identifier and start; other occurrences of a recurring event stay")
    func eventsFoldPerOccurrence() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext

        func event(_ start: Date) {
            let row = CDCalendarEvent(context: ctx)
            row.eventKitEventID = "EK-weekly"
            row.startDate = start
            row.endDate = start.addingTimeInterval(3600)
        }
        let monday = early
        let nextMonday = early.addingTimeInterval(7 * 86_400)
        event(monday)
        event(monday.addingTimeInterval(0.0004)) // the same instant as CloudKit stores it
        event(nextMonday)
        #expect(CoreDataTestHelpers.save(ctx))

        let removed = DataCleanupService.mergeSameEventKitEvents(using: ctx, container: nil)

        #expect(removed == 1)
        let starts = ctx.safeFetch(CDFetchRequest(CDCalendarEvent.self)).compactMap(\.startDate)
        #expect(starts.count == 2)
        #expect(starts.contains { abs($0.timeIntervalSince(nextMonday)) < 0.001 })
    }

    // MARK: - Templates

    @Test("Identical meeting templates fold, and the survivor stays active if any copy was")
    func meetingTemplatesFoldKeepingActive() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext

        func template(active: Bool, createdAt: Date) -> CDMeetingTemplate {
            let row = CDMeetingTemplate(context: ctx)
            row.name = "Standard Student Meeting"
            row.reflectionPrompt = "How has your work been going?"
            row.focusPrompt = "What would you like to focus on next?"
            row.isBuiltIn = true
            row.isActive = active
            row.createdAt = createdAt
            return row
        }
        let original = template(active: false, createdAt: early)
        _ = template(active: true, createdAt: late)
        _ = template(active: false, createdAt: late.addingTimeInterval(1))
        let other = CDMeetingTemplate(context: ctx)
        other.name = "Default"
        #expect(CoreDataTestHelpers.save(ctx))

        let removed = DataCleanupService.mergeIdenticalMeetingTemplates(using: ctx, container: nil)

        #expect(removed == 2)
        #expect(ctx.safeFetch(CDFetchRequest(CDMeetingTemplate.self)).count == 2)
        #expect(original.isActive)
    }

    @Test("The full dedup pass runs the same-source merges")
    func fullPassIncludesMerges() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        for _ in 0..<2 {
            let row = CDMeetingTemplate(context: ctx)
            row.name = "Standard Student Meeting"
            row.reflectionPrompt = "How has your work been going?"
        }
        #expect(CoreDataTestHelpers.save(ctx))

        let results = DataCleanupService.deduplicateAllModels(using: ctx)

        #expect(results["MeetingTemplate (identical)"] == 1)
        #expect(ctx.safeFetch(CDFetchRequest(CDMeetingTemplate.self)).count == 1)
    }
}

/// The persisted flag that holds zone repair and template seeding back
/// while a fresh store downloads from iCloud.
@Suite("First download gate")
struct FirstDownloadGateTests {

    @Test("Armed until opened, and opening reports only the first time")
    func armAndOpen() throws {
        let suiteName = "FirstDownloadGateTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(!FirstDownloadGate.isPending(defaults: defaults))
        #expect(!FirstDownloadGate.open(defaults: defaults))

        FirstDownloadGate.arm(defaults: defaults)
        #expect(FirstDownloadGate.isPending(defaults: defaults))

        #expect(FirstDownloadGate.open(defaults: defaults))
        #expect(!FirstDownloadGate.isPending(defaults: defaults))
        #expect(!FirstDownloadGate.open(defaults: defaults))
    }
}
