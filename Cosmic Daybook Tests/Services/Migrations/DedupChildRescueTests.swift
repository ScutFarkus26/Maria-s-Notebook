import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-05 (#8, #11, #12, #39, #54): deleting the copy of a record
// the cleanup drops took whatever it owned with it. Its cascade children
// (lesson attachments, track steps, a topic's solutions, a todo's subtasks)
// went too, a project's sessions came loose, and a work item's check-ins
// written by id alone were swept although the kept copy shares that id. The
// merges now move every child to the kept copy first, and copy nothing that
// would bring a retired value back.

@Suite("Dedup keeps the children of the copy it drops")
@MainActor
struct DedupChildRescueTests {

    private let early = Date(timeIntervalSinceReferenceDate: 780_000_000)
    private var late: Date { early.addingTimeInterval(60) }

    private func fetch<T: NSManagedObject>(_ type: T.Type, in context: NSManagedObjectContext) -> [T] {
        context.safeFetch(CDFetchRequest(T.self)).filter { !$0.isDeleted }
    }

    /// The two copies in the order the cleanup keeps them: survivor first.
    private func keptAndDropped<T: NSManagedObject>(_ first: T, _ second: T) -> (kept: T, dropped: T) {
        DataCleanupService.precedesAsCanonical(first, second, container: nil) ? (first, second) : (second, first)
    }

    /// Two copies of one work item, saved; the earlier-created copy is kept.
    private func twinWork(in context: NSManagedObjectContext) -> (kept: CDWorkModel, dropped: CDWorkModel) {
        let id = UUID()
        let kept = CoreDataTestHelpers.seedWorkModel(in: context, title: "Checkerboard")
        kept.id = id
        kept.createdAt = early
        let dropped = CoreDataTestHelpers.seedWorkModel(in: context, title: "Checkerboard")
        dropped.id = id
        dropped.createdAt = late
        return (kept, dropped)
    }

    // MARK: - Work and its check-ins (#11)

    @Test("A check-in linked to its work by id alone survives the work's duplicate cleanup")
    func idOnlyCheckInSurvivesWorkDedup() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let (kept, _) = twinWork(in: context)
        let checkIn = CDWorkCheckIn(context: context)
        checkIn.workID = try #require(kept.id).uuidString
        #expect(CoreDataTestHelpers.save(context))

        #expect(DataCleanupService.deduplicateWorkModelsStrong(using: context) == 1)

        let checkIns = fetch(CDWorkCheckIn.self, in: context)
        #expect(checkIns.count == 1)
        #expect(checkIns.first?.work === kept)
    }

    @Test("Deleting one copy of a work item leaves the id-only check-ins the other copy still has")
    func deletingOneCopyKeepsSharedCheckIns() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let (kept, dropped) = twinWork(in: context)
        let checkIn = CDWorkCheckIn(context: context)
        checkIn.workID = try #require(kept.id).uuidString
        #expect(CoreDataTestHelpers.save(context))

        context.delete(dropped)
        #expect(CoreDataTestHelpers.save(context))

        #expect(fetch(CDWorkCheckIn.self, in: context).count == 1)
    }

    // MARK: - Cascade children (#12)

    @Test("A lesson's attachments and sample works move to the kept copy")
    func lessonChildrenMove() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let id = UUID()
        let first = CoreDataTestHelpers.seedLesson(in: context, name: "Bead Chains")
        let second = CoreDataTestHelpers.seedLesson(in: context, name: "Bead Chains")
        first.id = id
        second.id = id
        #expect(CoreDataTestHelpers.save(context))
        let (kept, dropped) = keptAndDropped(first, second)
        let attachment = CDLessonAttachment(context: context)
        attachment.fileName = "chains.pdf"
        attachment.lesson = dropped
        let sampleWork = CDSampleWork(context: context)
        sampleWork.lesson = dropped
        #expect(CoreDataTestHelpers.save(context))

        #expect(DataCleanupService.deduplicateLessonsStrong(using: context) == 1)

        #expect(fetch(CDLessonAttachment.self, in: context).map(\.lesson) == [kept])
        #expect(fetch(CDSampleWork.self, in: context).count == 1)
        #expect(sampleWork.lesson === kept)
    }

    @Test("A track's steps and enrollments move to the kept copy")
    func trackChildrenMove() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let id = UUID()
        let kept = CDTrackEntity(context: context)
        kept.id = id
        kept.title = "Math — Laws"
        kept.createdAt = early
        let dropped = CDTrackEntity(context: context)
        dropped.id = id
        dropped.title = "Math — Laws"
        dropped.createdAt = late
        let step = CDTrackStep(context: context)
        step.lessonTemplateID = UUID()
        step.track = dropped
        let enrollment = CDStudentTrackEnrollmentEntity(context: context)
        enrollment.studentID = UUID().uuidString
        enrollment.trackID = id.uuidString
        enrollment.track = dropped
        #expect(CoreDataTestHelpers.save(context))

        let results = DataCleanupService.deduplicateAllModels(
            using: context, scope: DeduplicationScope(insertedEntities: ["Track"])
        )

        #expect(results["Track"] == 1)
        #expect(fetch(CDTrackStep.self, in: context).count == 1)
        #expect(step.track === kept)
        #expect(fetch(CDStudentTrackEnrollmentEntity.self, in: context).count == 1)
        #expect(enrollment.track === kept)
    }

    @Test("A community topic's proposed solutions and attachments move to the kept copy")
    func topicChildrenMove() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let id = UUID()
        let kept = CDCommunityTopicEntity(context: context)
        kept.id = id
        kept.title = "Lining up for recess"
        kept.createdAt = early
        let dropped = CDCommunityTopicEntity(context: context)
        dropped.id = id
        dropped.title = "Lining up for recess"
        dropped.createdAt = late
        let solution = CDProposedSolutionEntity(context: context)
        solution.topic = dropped
        let attachment = CDCommunityAttachment(context: context)
        attachment.topic = dropped
        #expect(CoreDataTestHelpers.save(context))

        let results = DataCleanupService.deduplicateAllModels(
            using: context, scope: DeduplicationScope(insertedEntities: ["CommunityTopic"])
        )

        #expect(results["CommunityTopic"] == 1)
        #expect(fetch(CDProposedSolutionEntity.self, in: context).count == 1)
        #expect(solution.topic === kept)
        #expect(fetch(CDCommunityAttachment.self, in: context).count == 1)
        #expect(attachment.topic === kept)
    }

    @Test("A todo's subtasks move to the kept copy")
    func todoSubtasksMove() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let id = UUID()
        let kept = CDTodoItem(context: context)
        kept.id = id
        kept.createdAt = early
        let dropped = CDTodoItem(context: context)
        dropped.id = id
        dropped.createdAt = late
        let subtask = CDTodoSubtask(context: context)
        subtask.todo = dropped
        #expect(CoreDataTestHelpers.save(context))

        let results = DataCleanupService.deduplicateAllModels(
            using: context, scope: DeduplicationScope(insertedEntities: ["TodoItem"])
        )

        #expect(results["TodoItem"] == 1)
        #expect(fetch(CDTodoSubtask.self, in: context).count == 1)
        #expect(subtask.todo === kept)
    }

    @Test("A project's sessions stay linked, to the kept copy")
    func projectSessionsMove() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let id = UUID()
        let kept = CDProject(context: context)
        kept.id = id
        kept.title = "Ancient Egypt"
        kept.createdAt = early
        let dropped = CDProject(context: context)
        dropped.id = id
        dropped.title = "Ancient Egypt"
        dropped.createdAt = late
        let session = CDProjectSession(context: context)
        session.projectID = id.uuidString
        session.project = dropped
        #expect(CoreDataTestHelpers.save(context))

        let results = DataCleanupService.deduplicateAllModels(
            using: context, scope: DeduplicationScope(insertedEntities: ["Project"])
        )

        #expect(results["Project"] == 1)
        #expect(session.project === kept)
    }

    // MARK: - Notes (#39, #54)

    @Test("The dropped work's note moves once; no second copy of its text is written")
    func workNoteMovesOnce() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let (kept, dropped) = twinWork(in: context)
        let note = CoreDataTestHelpers.seedNote(in: context, body: "Practiced the exchanges twice this week.")
        note.work = dropped
        #expect(CoreDataTestHelpers.save(context))

        #expect(DataCleanupService.deduplicateWorkModelsStrong(using: context) == 1)

        let notes = fetch(CDNote.self, in: context)
        #expect(notes.count == 1)
        #expect(notes.first?.body == "Practiced the exchanges twice this week.")
        #expect(notes.first?.work === kept)
    }

    @Test("A note's practice session and issue carry over to the kept copy")
    func noteKeepsSessionAndIssue() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let id = UUID()
        let kept = CoreDataTestHelpers.seedNote(in: context, body: "Worked well together.")
        kept.id = id
        kept.createdAt = early
        let dropped = CoreDataTestHelpers.seedNote(in: context, body: "Worked well together.")
        dropped.id = id
        dropped.createdAt = late
        let session = CDPracticeSession(context: context)
        let issue = CDIssue(context: context)
        dropped.practiceSession = session
        dropped.issue = issue
        #expect(CoreDataTestHelpers.save(context))

        #expect(DataCleanupService.deduplicateNotesStrong(using: context) == 1)

        #expect(kept.practiceSession === session)
        #expect(kept.issue === issue)
    }

    // MARK: - The retired completion outcome (#8)

    @Test("Setting a work item's status clears the retired completion outcome")
    func statusSetterClearsOutcome() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let work = CoreDataTestHelpers.seedWorkModel(in: context)
        work.statusRaw = "complete"
        work.completionOutcomeRaw = "mastered"

        work.status = .active

        #expect(work.completionOutcomeRaw == nil)
    }

    @Test("An old mastered row, reopened and marked Done, stays Done through the launch pass")
    func reopenedThenDoneStaysDone() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let work = CoreDataTestHelpers.seedWorkModel(in: context)
        work.statusRaw = "complete"
        work.completionOutcomeRaw = "mastered"
        #expect(CoreDataTestHelpers.save(context))
        DataCleanupService.mergeWorkCompletionOutcomes(using: context)
        #expect(work.status == .mastered)

        work.status = .active
        work.status = .done
        #expect(CoreDataTestHelpers.save(context))
        DataCleanupService.mergeWorkCompletionOutcomes(using: context)

        #expect(work.status == .done)
    }

    @Test("Dedup doesn't copy a retired outcome onto the kept copy")
    func dedupLeavesOutcomeBehind() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let (kept, dropped) = twinWork(in: context)
        kept.status = .done
        dropped.statusRaw = "complete"
        dropped.completionOutcomeRaw = "mastered"
        #expect(CoreDataTestHelpers.save(context))

        #expect(DataCleanupService.deduplicateWorkModelsStrong(using: context) == 1)
        DataCleanupService.mergeWorkCompletionOutcomes(using: context)

        #expect(kept.completionOutcomeRaw == nil)
        #expect(kept.status == .done)
    }
}
