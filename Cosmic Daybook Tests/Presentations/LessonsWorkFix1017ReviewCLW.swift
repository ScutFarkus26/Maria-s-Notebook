import Combine
import CoreData
import CoreGraphics
import Foundation
import Testing
@testable import CosmicDaybook

// Review (c) of the 2026-10-17 bug-hunt fixes, part L: a several-card drag
// carried the selection in id order rather than the order on screen; a card
// merged by a drop was still given a time; a failed drop save was silent and
// left the drop half done; the presentation history redrew on every
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

    private func dropDelegate(
        day: Date,
        all: [CDLessonAssignment],
        column: [(id: UUID, frame: CGRect)],
        context: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator
    ) -> WeekDayColumnDropDelegate {
        WeekDayColumnDropDelegate(
            calendar: AppCalendar.shared,
            viewContext: context,
            saveCoordinator: saveCoordinator,
            allLessonAssignments: all,
            day: day,
            orderedPresentationIDs: { column.map(\.id) },
            itemFramesProvider: { Dictionary(uniqueKeysWithValues: column.map { ($0.id, $0.frame) }) },
            onDropWorkCheckIns: { _, _ in },
            onDropWork: { _, _ in },
            onTargetChange: { _ in },
            onInsertionIndexChange: { _ in }
        )
    }

    // MARK: - #47 The order a selection is dragged in

    @Test("#47: a dragged selection carries its cards in the order they are on screen")
    func dragPayloadFollowsDisplayOrder() {
        let first = UUID(), second = UUID(), third = UUID()
        let selection = WorkspaceMultiSelection()
        // Selected out of order; on screen first, second, third.
        for id in [third, first, second] { selection.toggle(id) }

        let payload = selection.dragPayload(
            startingAt: second,
            inOrder: [first, second, third],
            make: UnifiedCalendarDragPayload.presentation
        )

        #expect(UnifiedCalendarDragPayload.parseAll(payload) == [first, second, third].map { .presentation($0) })
    }

    // MARK: - #47 A card merged by the drop

    @Test("#47: a card merged into another by a drop is not given a time afterward")
    func mergedCardIsNotRescheduled() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let monday = try monday()
        let tuesday = try #require(AppCalendar.shared.date(byAdding: .day, value: 1, to: monday))
        let lessonID = UUID().uuidString
        let target = scheduled(on: monday, lessonID: lessonID, in: context)
        let source = scheduled(on: monday, lessonID: lessonID, in: context)
        let other = scheduled(on: tuesday, in: context)
        target.setScheduledFor(
            AppCalendar.shared.date(bySettingHour: 9, minute: 0, second: 0, of: monday), using: AppCalendar.shared
        )
        source.setScheduledFor(
            AppCalendar.shared.date(bySettingHour: 9, minute: 0, second: 1, of: monday), using: AppCalendar.shared
        )
        #expect(CoreDataTestHelpers.save(context))
        let targetID = try #require(target.id), sourceID = try #require(source.id), otherID = try #require(other.id)
        let sourceStudents = source.studentIDs

        // Monday's second card and Tuesday's, dropped together on Monday's first card.
        let delegate = dropDelegate(
            day: monday,
            all: [target, source, other],
            column: [
                (targetID, CGRect(x: 0, y: 0, width: 200, height: 40)),
                (sourceID, CGRect(x: 0, y: 40, width: 200, height: 40))
            ],
            context: context,
            saveCoordinator: .preview
        )
        let text = UnifiedCalendarDragPayload.joined([.presentation(sourceID), .presentation(otherID)])
        delegate.handleDroppedText(text, location: CGPoint(x: 100, y: 20))

        // The source joined the card it was dropped on and is gone.
        #expect(source.managedObjectContext == nil || source.isDeleted)
        #expect(Set(sourceStudents).isSubset(of: Set(target.studentIDs)))
        let lookup = CDFetchRequest(CDLessonAssignment.self)
        lookup.predicate = NSPredicate(format: "id == %@", sourceID as CVarArg)
        #expect(context.safeFetch(lookup).isEmpty)
        // The other card landed on Monday with a time of its own, and all of it saved.
        #expect(other.scheduledForDay == monday)
        let targetTime = try #require(target.scheduledFor)
        let otherTime = try #require(other.scheduledFor)
        #expect(targetTime != otherTime)
        #expect(!context.hasChanges)
    }

    // MARK: - #47 A drop whose save fails

    @Test("#47: a drop whose save fails says so and leaves the cards where they were")
    func failedDropSaveIsReportedAndUndone() async throws {
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        let monday = try monday()
        let tuesday = try #require(AppCalendar.shared.date(byAdding: .day, value: 1, to: monday))
        let existing = scheduled(on: monday, in: context)
        let dropped = scheduled(on: tuesday, in: context)
        try context.save()
        let existingTime = existing.scheduledFor
        let existingID = try #require(existing.id), droppedID = try #require(dropped.id)

        // Another device's edit lands in the store under this context, so the
        // drop's save conflicts (this context keeps the default error policy).
        let background = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        background.persistentStoreCoordinator = context.persistentStoreCoordinator
        let objectID = dropped.objectID
        await background.perform {
            guard let elsewhere = try? background.existingObject(with: objectID) as? CDLessonAssignment else { return }
            elsewhere.notes = "Edited elsewhere"
            try? background.save()
        }

        let saveCoordinator = SaveCoordinator()
        let delegate = dropDelegate(
            day: monday,
            all: [existing, dropped],
            column: [(existingID, CGRect(x: 0, y: 0, width: 200, height: 40))],
            context: context,
            saveCoordinator: saveCoordinator
        )
        delegate.handleDroppedText(
            UnifiedCalendarDragPayload.presentation(droppedID).stringRepresentation,
            location: CGPoint(x: 100, y: 120)
        )

        // The guide is told, in the shared save alert.
        #expect(saveCoordinator.lastSaveError != nil)
        #expect(saveCoordinator.isShowingSaveError)
        // Nothing half-done is left pending: both cards read what the store has.
        #expect(!dropped.hasChanges)
        #expect(!existing.hasChanges)
        #expect(dropped.scheduledForDay == tuesday)
        #expect(existing.scheduledFor == existingTime)
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
