import Combine
import CoreData
import CoreGraphics
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-17, findings #45–#48: screens that watched a narrower
// signal than what they draw (the presentation history, the Progress
// dashboard, the practice lists), a several-card drop that placed each card
// against the column as it was drawn, and a batch Mark Presented that went
// through the toggle.

@Suite("Lessons, presentations and work (bug hunt 2026-10-17)")
@MainActor
struct LessonsWorkFix1017LW {

    @MainActor
    private final class Counter {
        var value = 0
    }

    @MainActor
    private final class Scopes {
        var seen: [Set<String>] = []
    }

    private func waitUntil(_ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    /// Runs everything already queued on the main queue, twice, so a delivery
    /// queued by a block that was queued runs too.
    private func drainMainQueue() async {
        for _ in 0..<2 {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    // MARK: - #45 The presentation history

    @Test("#45: an edit to a given presentation that leaves the count alone still reloads the history")
    func historyReloadsOnEditWithUnchangedCount() {
        // Moving Tuesday's lesson to Monday, adding a child, an MCP re-date:
        // the number of given presentations doesn't move, the rows do.
        #expect(LessonAssignmentHistoryView.assignmentChangeResponse(newCount: 12, lastCount: 12) == .redraw)
        // A failed count still redraws what is loaded.
        #expect(LessonAssignmentHistoryView.assignmentChangeResponse(newCount: nil, lastCount: 12) == .redraw)
        // One given or taken back: the page itself is fetched again.
        #expect(LessonAssignmentHistoryView.assignmentChangeResponse(newCount: 13, lastCount: 12) == .refetchPage)
        #expect(LessonAssignmentHistoryView.assignmentChangeResponse(newCount: 11, lastCount: 12) == .refetchPage)
        // One taken back while another was given: the count holds, the page doesn't.
        #expect(LessonAssignmentHistoryView.assignmentChangeResponse(
            newCount: 12, lastCount: 12, loadedRowsStillGiven: false
        ) == .refetchPage)
    }

    // MARK: - #46 The Progress dashboard

    @Test("#46: the Progress dashboard reloads on mastery marks and lesson edits too")
    func progressDashboardWatchesMasteryAndLessons() throws {
        let watched = ProgressDashboardView.reloadEntityNames
        #expect(watched == ["LessonAssignment", "WorkModel", "LessonPresentation", "Lesson"])
        // The remote-import signal reports only these, so all four must be among them.
        #expect(watched.isSubset(of: PersistentHistoryProcessor.presentationEntityNames))

        // A mastery mark saved alone (what mark_mastered and a synced mark
        // write) is seen; so is a lesson rename.
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context)
        let mark = CDLessonPresentation(context: context)
        mark.studentID = UUID().uuidString
        mark.lessonID = lesson.id?.uuidString ?? ""
        mark.state = .presented
        #expect(CoreDataTestHelpers.save(context))

        let touched = Scopes()
        let center = NotificationCenter.default
        let token = center.addObserver(forName: .NSManagedObjectContextDidSave, object: context, queue: nil) { note in
            let scope = ManagedObjectChangeScope.touched(watched, in: note.userInfo)
            MainActor.assumeIsolated { touched.seen.append(scope) }
        }
        defer { center.removeObserver(token) }

        mark.state = .proficient
        mark.masteredAt = Date()
        #expect(CoreDataTestHelpers.save(context))
        lesson.name = "Renamed"
        #expect(CoreDataTestHelpers.save(context))

        #expect(touched.seen == [["LessonPresentation"], ["Lesson"]])
    }

    // MARK: - #47 Dropping several presentations on a day

    @Test("#47: three presentations dropped on a day keep their order and get distinct times")
    func batchDropKeepsOrderAndDistinctTimes() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let calendar = AppCalendar.shared
        let monday = AppCalendar.startOfDay(try #require(
            calendar.date(from: DateComponents(year: 2026, month: 6, day: 8))
        ))
        let tuesday = try #require(calendar.date(byAdding: .day, value: 1, to: monday))

        func scheduled(on day: Date) -> CDLessonAssignment {
            let assignment = CDLessonAssignment(context: context)
            // A lesson each, so no drop is read as a merge.
            assignment.lessonID = UUID().uuidString
            assignment.studentIDs = [UUID().uuidString]
            assignment.schedule(onDay: day)
            return assignment
        }
        let existing = scheduled(on: monday)
        let dropped = [scheduled(on: tuesday), scheduled(on: tuesday), scheduled(on: tuesday)]
        #expect(CoreDataTestHelpers.save(context))
        let existingID = try #require(existing.id)
        let droppedIDs = try dropped.map { try #require($0.id) }

        // Monday as drawn: one card, 40 points tall.
        let delegate = WeekDayColumnDropDelegate(
            calendar: calendar,
            viewContext: context,
            saveCoordinator: .preview,
            allLessonAssignments: [existing] + dropped,
            day: monday,
            orderedPresentationIDs: { [existingID] },
            itemFramesProvider: { [existingID: CGRect(x: 0, y: 0, width: 200, height: 40)] },
            onDropWorkCheckIns: { _, _ in },
            onDropWork: { _, _ in },
            onTargetChange: { _ in },
            onInsertionIndexChange: { _ in }
        )
        // A command-click selection of all three, picked out of order and
        // dragged by the middle one, dropped below the card: the payload is
        // the one the backlog line builds, in the order on screen.
        let selection = WorkspaceMultiSelection()
        for id in droppedIDs.reversed() { selection.toggle(id) }
        let text = selection.dragPayload(
            startingAt: droppedIDs[1], inOrder: droppedIDs, make: UnifiedCalendarDragPayload.presentation
        )
        delegate.handleDroppedText(text, location: CGPoint(x: 100, y: 120))

        let times = dropped.compactMap(\.scheduledFor)
        #expect(times.count == 3)
        #expect(dropped.allSatisfy { $0.scheduledForDay == monday })
        // In the order they were dragged, each after the one before, all below Monday's card.
        let existingTime = try #require(existing.scheduledFor)
        #expect(times == times.sorted())
        #expect(Set(times).count == 3)
        #expect(times.allSatisfy { $0 > existingTime })
        // Saved, once, with nothing left pending.
        #expect(!context.hasChanges)
    }

    @Test("#47: a single drop still lands where it is dropped")
    func singleDropStillReorders() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let calendar = AppCalendar.shared
        let monday = AppCalendar.startOfDay(try #require(
            calendar.date(from: DateComponents(year: 2026, month: 6, day: 8))
        ))
        func scheduled() -> CDLessonAssignment {
            let assignment = CDLessonAssignment(context: context)
            assignment.lessonID = UUID().uuidString
            assignment.studentIDs = [UUID().uuidString]
            assignment.schedule(onDay: monday)
            return assignment
        }
        let first = scheduled(), second = scheduled()
        first.setScheduledFor(calendar.date(bySettingHour: 9, minute: 0, second: 0, of: monday), using: calendar)
        second.setScheduledFor(calendar.date(bySettingHour: 9, minute: 0, second: 1, of: monday), using: calendar)
        #expect(CoreDataTestHelpers.save(context))
        let firstID = try #require(first.id), secondID = try #require(second.id)

        let delegate = WeekDayColumnDropDelegate(
            calendar: calendar,
            viewContext: context,
            saveCoordinator: .preview,
            allLessonAssignments: [first, second],
            day: monday,
            orderedPresentationIDs: { [firstID, secondID] },
            itemFramesProvider: {
                [firstID: CGRect(x: 0, y: 0, width: 200, height: 40),
                 secondID: CGRect(x: 0, y: 40, width: 200, height: 40)]
            },
            onDropWorkCheckIns: { _, _ in },
            onDropWork: { _, _ in },
            onTargetChange: { _ in },
            onInsertionIndexChange: { _ in }
        )
        // The second card dragged above the first.
        delegate.handleDroppedText(UnifiedCalendarDragPayload.presentation(secondID).stringRepresentation,
                                   location: CGPoint(x: 100, y: 5))
        let firstTime = try #require(first.scheduledFor)
        let secondTime = try #require(second.scheduledFor)
        #expect(secondTime < firstTime)
    }

    // MARK: - #48 Practice lists

    @Test("#48: the practice signal fires for practice sessions saved on another context, not other entities")
    func practiceSignalSeesOtherContextsSaves() async throws {
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        context.automaticallyMergesChangesFromParent = true
        let background = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        background.persistentStoreCoordinator = context.persistentStoreCoordinator

        let received = Counter()
        let subscription = CoordinatorChangeSignal.changes(of: ["PracticeSession"], in: context)
            .sink { _ in received.value += 1 }
        defer { subscription.cancel() }

        // Another entity saved elsewhere: nothing.
        await background.perform {
            let lesson = CDLesson(context: background)
            lesson.name = "Elsewhere"
            try? background.save()
        }
        await drainMainQueue()
        #expect(received.value == 0)

        // A practice session saved on another context (an MCP write, a
        // session logged in another window), which this context never had
        // registered: seen.
        await background.perform {
            let session = CDPracticeSession(context: background)
            session.date = Date()
            try? background.save()
        }
        #expect(try await waitUntil { received.value > 0 })

        // An unsaved edit on this context: seen too.
        let baseline = received.value
        let local = CDPracticeSession(context: context)
        local.date = Date()
        context.processPendingChanges()
        await drainMainQueue()
        #expect(received.value > baseline)
    }

    // MARK: - #48 Batch Mark Presented

    @Test("#48: a batch Mark Presented on a stale grid never takes a child off a presentation")
    func batchMarkPresentedOnlyAdds() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Test")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Decimal 0", area: "Math", sequence: "Decimal")
        try context.save()
        let adaID = try #require(ada.id)
        let lessonID = try #require(lesson.id)

        // Given to Ada on another device after this grid was drawn.
        let given = CDLessonAssignment(context: context)
        given.lessonID = lessonID.uuidString
        given.studentIDs = [ada.cloudKitKey]
        given.markPresented(at: Date())
        try context.save()

        for previously in [false, true] {
            let cells: Set<CellIdentifier> = [CellIdentifier(studentID: adaID, lessonID: lessonID)]
            // The grid still shows her as not presented.
            if previously {
                ChecklistBatchActionExecutor.batchMarkPreviouslyPresented(
                    selectedCells: cells, students: [ada], lessons: [lesson], matrixStates: [:], context: context
                )
            } else {
                ChecklistBatchActionExecutor.batchMarkPresented(
                    selectedCells: cells, students: [ada], lessons: [lesson], matrixStates: [:], context: context
                )
            }
            let request = CDFetchRequest(CDLessonAssignment.self)
            request.predicate = NSPredicate(format: "lessonID == %@", lessonID.uuidString)
            let presentedForAda = context.safeFetch(request).filter {
                $0.isPresented && $0.studentIDs.contains(ada.cloudKitKey)
            }
            #expect(!presentedForAda.isEmpty, "previously: \(previously)")
            #expect(given.studentIDs == [ada.cloudKitKey], "previously: \(previously)")
        }
    }
}
