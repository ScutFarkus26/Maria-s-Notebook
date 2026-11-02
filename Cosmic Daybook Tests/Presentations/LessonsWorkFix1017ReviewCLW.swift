import Combine
import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Review (c) of the 2026-10-17 bug-hunt fixes, part L: the presentation
// history redrew on every
// presentation change and missed given ones outside its page; and the
// practice signal fired twice for one save made elsewhere.

@Suite("Lessons and work, review fixes (bug hunt 2026-10-17)")
@MainActor
struct LessonsWorkFix1017ReviewCLW {

    @MainActor
    private final class Counter {
        var value = 0
    }

    @MainActor
    private final class Received {
        var touches: [LessonAssignmentHistoryView.AssignmentTouches] = []
    }

    private func waitUntil(_ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    private func monday() throws -> Date {
        AppCalendar.startOfDay(try #require(
            AppCalendar.shared.date(from: DateComponents(year: 2026, month: 6, day: 8))
        ))
    }

    private func scheduled(
        on day: Date, lessonID: String = UUID().uuidString, in context: NSManagedObjectContext
    ) -> CDLessonAssignment {
        let assignment = CDLessonAssignment(context: context)
        assignment.lessonID = lessonID
        assignment.studentIDs = [UUID().uuidString]
        assignment.schedule(onDay: day)
        return assignment
    }

    // MARK: - #45 The presentation history

    @Test("#45: the history redraws only for rows it shows, and fetches again for a given one it doesn't")
    func historyResponseReadsTouchedRows() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let monday = try monday()
        let loaded = CDLessonAssignment(context: context)
        loaded.lessonID = UUID().uuidString
        loaded.markPresented(at: monday)
        let givenElsewhere = CDLessonAssignment(context: context)
        givenElsewhere.lessonID = UUID().uuidString
        givenElsewhere.markPresented(at: monday)
        let planned = scheduled(on: monday, in: context)
        try context.save()

        let loadedIDs: Set<NSManagedObjectID> = [loaded.objectID]
        func response(
            _ touches: LessonAssignmentHistoryView.AssignmentTouches, newCount: Int? = 2
        ) -> LessonAssignmentHistoryView.AssignmentChangeResponse {
            LessonAssignmentHistoryView.assignmentChangeResponse(
                touches: touches,
                loadedIDs: loadedIDs,
                isGiven: { LessonAssignmentHistoryView.isGivenPresentation($0, in: context) },
                newCount: newCount,
                lastCount: 2
            )
        }

        // A planned lesson moved on the calendar: not a row here.
        #expect(response(.objects([planned.objectID])) == .ignore)
        // A row on the page re-dated or re-rostered: drawn again.
        #expect(response(.objects([loaded.objectID])) == .redraw)
        // A given presentation outside the page edited (re-dated into it, say): fetched again.
        #expect(response(.objects([givenElsewhere.objectID])) == .refetchPage)
        // A remote import names only the table: drawn again, as before.
        #expect(response(.unknown) == .redraw)
        // The count rule still comes first.
        #expect(response(.objects([planned.objectID]), newCount: 3) == .refetchPage)
    }

    @Test("#45: the history's change signal carries the presentations a save touched")
    func historyChangeSignalCarriesObjectIDs() async throws {
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        let background = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        background.persistentStoreCoordinator = context.persistentStoreCoordinator

        let received = Received()
        let subscription = LessonAssignmentHistoryView.assignmentTouches(in: context)
            .sink { received.touches.append($0) }
        defer { subscription.cancel() }

        // Saved on another context (an MCP write): its id.
        let savedID = await background.perform {
            let assignment = CDLessonAssignment(context: background)
            assignment.lessonID = UUID().uuidString
            assignment.markPresented(at: Date())
            try? background.save()
            return assignment.objectID
        }
        #expect(try await waitUntil { !received.touches.isEmpty })
        #expect(received.touches.last == .objects([savedID]))

        // A remote import, which names only the table: unknown.
        NotificationCenter.default.post(
            name: .presentationDataDidChange,
            object: nil,
            userInfo: [PersistentHistoryProcessor.changedEntityNamesKey: Set(["LessonAssignment"])]
        )
        #expect(try await waitUntil { received.touches.count >= 2 })
        #expect(received.touches.last == .unknown)

        // Another table saved elsewhere: nothing.
        let before = received.touches.count
        await background.perform {
            let lesson = CDLesson(context: background)
            lesson.name = "Elsewhere"
            try? background.save()
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(received.touches.count == before)
    }

    // MARK: - #48 Practice lists

    @Test("#48: one save made elsewhere reaches a practice list once")
    func practiceSignalCoalescesAForeignSave() async throws {
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        context.automaticallyMergesChangesFromParent = true
        let session = CDPracticeSession(context: context)
        session.date = Date()
        try context.save()
        let background = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        background.persistentStoreCoordinator = context.persistentStoreCoordinator

        let raw = Counter(), coalesced = Counter()
        let rawSubscription = CoordinatorChangeSignal.changes(of: ["PracticeSession"], in: context)
            .sink { _ in raw.value += 1 }
        let subscription = CoordinatorChangeSignal.coalescedChanges(of: ["PracticeSession"], in: context)
            .sink { _ in coalesced.value += 1 }
        defer {
            rawSubscription.cancel()
            subscription.cancel()
        }

        // The session this screen shows, edited on another context: the save
        // and its merge into this context are two raw signals.
        let objectID = session.objectID
        await background.perform {
            guard let elsewhere = try? background.existingObject(with: objectID) as? CDPracticeSession else { return }
            elsewhere.date = Date().addingTimeInterval(60)
            try? background.save()
        }
        #expect(try await waitUntil { coalesced.value > 0 })
        try await Task.sleep(for: .milliseconds(600))
        #expect(raw.value >= 2)
        #expect(coalesced.value == 1)
    }
}
