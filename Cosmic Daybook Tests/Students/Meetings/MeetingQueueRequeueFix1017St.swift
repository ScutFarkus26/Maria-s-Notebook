import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-17, #40: a child put back in the Meetings queue by hand
/// stayed in Up Next after her meeting was filed through Claude, because
/// `create_meeting_entry` stores the meeting at midnight, which reads as
/// earlier than the requeue's 10:15. The requeue now ends when a new meeting
/// row appears, whatever its date.
@Suite("Meetings queue requeue (fix 10-17 St)")
struct MeetingQueueRequeueFix1017StTests {

    private let calendar = AppCalendar.shared

    private var midnight: Date { calendar.startOfDay(for: Date()) }
    private var quarterPastTen: Date { midnight.addingTimeInterval(10 * 3600 + 15 * 60) }
    private var yesterday: Date { midnight.addingTimeInterval(-86_400) }

    @Test("A meeting filed after the requeue ends it, even one dated midnight that day")
    func newMeetingRowEndsTheRequeue() {
        let child = UUID()
        let earlier = UUID()
        var store = MeetingQueueRequeueStore()
        let before = [child: MeetingQueueSignals(lastMet: yesterday, meetingIDs: [earlier])]
        store.requeue(child, signals: before, now: quarterPastTen)
        #expect(store.activeIDs(signals: before) == [child])

        // Filed through Claude after 10:15, stored at midnight.
        let after = [child: MeetingQueueSignals(lastMet: midnight, meetingIDs: [earlier, UUID()])]
        #expect(store.activeIDs(signals: after).isEmpty)
    }

    @Test("A meeting deleted after the requeue doesn't end it")
    func deletedMeetingKeepsTheRequeue() {
        let child = UUID()
        let first = UUID(), second = UUID()
        var store = MeetingQueueRequeueStore()
        store.requeue(
            child, signals: [child: MeetingQueueSignals(lastMet: yesterday, meetingIDs: [first, second])],
            now: quarterPastTen
        )
        let fewer = [child: MeetingQueueSignals(lastMet: yesterday, meetingIDs: [first])]
        #expect(store.activeIDs(signals: fewer) == [child])
    }

    @Test("The meetings she had are kept across launches")
    func meetingIDsSurviveSaveAndLoad() throws {
        let suite = "MeetingQueueRequeueFix1017St.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let child = UUID()
        let earlier = UUID()
        var store = MeetingQueueRequeueStore()
        store.requeue(child, signals: [child: MeetingQueueSignals(meetingIDs: [earlier])], now: quarterPastTen)
        store.save(defaults: defaults)

        let loaded = MeetingQueueRequeueStore.load(defaults: defaults)
        #expect(loaded.entries == store.entries)
        let after = [child: MeetingQueueSignals(lastMet: midnight, meetingIDs: [earlier, UUID()])]
        #expect(loaded.activeIDs(signals: after).isEmpty)
    }

    @Test("A requeue saved before this change still loads, and ends at a later meeting")
    func legacyEntryStillLoads() throws {
        let suite = "MeetingQueueRequeueFix1017St.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let child = UUID()
        defaults.set([child.uuidString: quarterPastTen], forKey: UserDefaultsKeys.meetingsWorkflowRequeuedStudents)

        let loaded = MeetingQueueRequeueStore.load(defaults: defaults)
        #expect(loaded.entries[child]?.requeuedAt == quarterPastTen)
        let stillWaiting = [child: MeetingQueueSignals(lastMet: yesterday, meetingIDs: [UUID()])]
        #expect(loaded.activeIDs(signals: stillWaiting) == [child])
        let later = quarterPastTen.addingTimeInterval(60)
        let metLater = [child: MeetingQueueSignals(lastMet: later, meetingIDs: [UUID()])]
        #expect(loaded.activeIDs(signals: metLater).isEmpty)
    }

    @Test("The queue knows every meeting row each child has")
    @MainActor
    func queueSignalsCarryMeetingIDs() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let child = UUID()
        var ids = Set<UUID>()
        for date in [yesterday, nil] {
            let meeting = CDStudentMeeting(context: context)
            meeting.studentID = child.uuidString
            meeting.date = date
            ids.insert(try #require(meeting.id))
        }
        #expect(CoreDataTestHelpers.save(context))

        let queue = MeetingQueueModel()
        queue.refreshIfNeeded(context: context, workOverdueDays: 14)
        #expect(queue.signals[child]?.meetingIDs == ids)
        #expect(queue.signals[child]?.lastMet == yesterday)
    }
}
