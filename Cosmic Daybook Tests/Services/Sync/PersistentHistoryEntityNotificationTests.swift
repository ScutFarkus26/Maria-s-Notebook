import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// The Upcoming pane and the progress map used to keep four whole tables
// registered through `@FetchRequest` purely to notice a remote change. The
// history processor already reads which entities a batch touched, so it now
// posts `.presentationDataDidChange` for the four they read — and nothing for
// a batch that touched none of them.

@Suite("Persistent history: entity-scoped notifications")
@MainActor
struct PersistentHistoryEntityNotificationTests {

    /// Main-actor mailbox for the posted notification's touched entity names.
    @MainActor
    private final class Mailbox {
        var received: [Set<String>] = []
    }

    private func waitUntil(
        timeout: Duration = .seconds(30),
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    // MARK: - Which batches owe the notification

    @Test("A batch touching a presentation entity owes the presentation notification")
    func presentationEntitiesOweTheNotification() {
        for name in PersistentHistoryProcessor.presentationEntityNames {
            let notices = PersistentHistoryProcessor.entityNotices(for: [name, "Note"])
            #expect(notices.presentation && !notices.schoolDay, "\(name)")
        }
    }

    @Test("A batch touching only unrelated entities owes nothing")
    func unrelatedEntitiesOweNothing() {
        let unrelated = PersistentHistoryProcessor.entityNotices(for: ["Note", "Observation"])
        #expect(!unrelated.presentation && !unrelated.schoolDay)
        let empty = PersistentHistoryProcessor.entityNotices(for: [])
        #expect(!empty.presentation && !empty.schoolDay)
    }

    @Test("A calendar batch owes only the school-day notification; a mixed batch owes both")
    func calendarAndMixedBatches() {
        let calendar = PersistentHistoryProcessor.entityNotices(for: ["NonSchoolDay"])
        #expect(calendar.schoolDay && !calendar.presentation)
        let both = PersistentHistoryProcessor.entityNotices(for: ["SchoolDayOverride", "Student"])
        #expect(both.schoolDay && both.presentation)
    }

    @Test("The watched entity names exist in the model")
    func watchedNamesExistInTheModel() throws {
        let model = try CoreDataTestHelpers.makeInMemoryStack().container.managedObjectModel
        let known = Set(model.entitiesByName.keys)
        #expect(PersistentHistoryProcessor.presentationEntityNames.isSubset(of: known))
    }

    // MARK: - The post itself

    @Test("Posting carries only the touched presentation entities in userInfo")
    func postCarriesTouchedNames() async {
        let mailbox = Mailbox()
        let observer = NotificationCenter.default.addObserver(
            forName: .presentationDataDidChange, object: nil, queue: .main
        ) { note in
            let names = note.userInfo?[PersistentHistoryProcessor.changedEntityNamesKey] as? Set<String> ?? []
            MainActor.assumeIsolated { mailbox.received.append(names) }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        // An unrelated batch creates no post at all (see `unrelatedEntitiesOweNothing`),
        // so only the mixed batch below can produce this exact set.
        PersistentHistoryProcessor.postEntityNotifications(for: ["Note"])
        PersistentHistoryProcessor.postEntityNotifications(for: ["WorkModel", "Note", "LessonAssignment"])

        let expected: Set<String> = ["WorkModel", "LessonAssignment"]
        let arrived = await waitUntil { mailbox.received.contains(expected) }
        #expect(arrived, "expected a post naming exactly \(expected.sorted()), got \(mailbox.received)")
    }
}
