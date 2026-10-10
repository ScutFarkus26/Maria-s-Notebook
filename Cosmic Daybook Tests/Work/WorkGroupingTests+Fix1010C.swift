import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-10, P1 #17: copies made together stay linked when the
/// children had the lesson on different days (`createWork` gives each copy
/// that child's own latest presentation) or when one copy was renamed. With
/// both creation dates, the minute decides; title and presentation decide only
/// when that minute holds two assignments for the same children.
@Suite("Work Grouping: copies made together (fix 10-10 C)")
@MainActor
struct WorkGroupingFix1010CTests {

    private struct Fixture {
        let context: NSManagedObjectContext
        let lessonID: UUID
        let maya: UUID
        let eli: UUID
    }

    /// A lesson, two enrolled children, and a given presentation for each on
    /// a different day — Maya on Sep 1, Eli on Sep 8.
    private func makeFixture() throws -> Fixture {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Commutative Law")
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        let eli = CoreDataTestHelpers.seedStudent(in: context, firstName: "Eli", lastName: "Park")
        let lessonID = try #require(lesson.id)
        let mayaID = try #require(maya.id)
        let eliID = try #require(eli.id)
        for (studentID, day) in [(mayaID, "2026-09-01"), (eliID, "2026-09-08")] {
            let given = CDLessonAssignment(context: context)
            given.lessonID = lessonID.uuidString
            given.studentIDs = [studentID.uuidString]
            given.markPresented(at: try CoreDataTestHelpers.day(day), snapshotLesson: false)
        }
        CoreDataTestHelpers.save(context)
        return Fixture(context: context, lessonID: lessonID, maya: mayaID, eli: eliID)
    }

    /// One Quick New Work for both children: `createWork` per child, then a
    /// participant row naming each other child, as the sheet does.
    private func quickNewWork(
        _ fixture: Fixture, title: String = "Commutative law follow-up", for students: [UUID]? = nil
    ) throws -> [CDWorkModel] {
        let repository = WorkRepository(context: fixture.context)
        let works = try (students ?? [fixture.maya, fixture.eli]).map { studentID in
            try repository.createWork(
                studentID: studentID, lessonID: fixture.lessonID, title: title,
                kind: .followUpAssignment, saveImmediately: false
            )
        }
        for work in works {
            for other in works where other !== work {
                let participant = CDWorkParticipantEntity(context: fixture.context)
                participant.id = UUID()
                participant.studentID = other.studentID
                participant.work = work
            }
        }
        CoreDataTestHelpers.save(fixture.context)
        return works
    }

    private func members(of work: CDWorkModel, in context: NSManagedObjectContext) -> Set<NSManagedObjectID> {
        Set(WorkGrouping.group(containing: work, in: context).members.map(\.objectID))
    }

    // MARK: - Different presentation days

    @Test("children who had the lesson on different days get one group from one Quick New Work")
    func differentPresentationDaysStayLinked() throws {
        let fixture = try makeFixture()
        let works = try quickNewWork(fixture)
        // The copies really do carry different presentations.
        #expect(works[0].presentationID != nil)
        #expect(works[0].presentationID != works[1].presentationID)

        #expect(WorkGrouping.areLinkedCopies(works[0], works[1]))
        let group = WorkGrouping.group(containing: works[0], in: fixture.context)
        #expect(group.shape == .linkedCopies(total: 2))
        #expect(members(of: works[1], in: fixture.context) == Set(works.map(\.objectID)))
    }

    @Test("closing Maya's copy writes Maya's completion only, and leaves Eli's copy open")
    func closingOneCopyStaysOnThatChild() throws {
        let fixture = try makeFixture()
        let works = try quickNewWork(fixture)
        let mayas = works[0]
        let elis = works[1]

        let rows = try WorkLogTargets.resolve(work: mayas, students: [fixture.maya], in: fixture.context)
        #expect(rows.map(\.objectID) == [mayas.objectID])
        try WorkLogService.log(rows.map { .init(work: $0, status: .mastered) }, context: fixture.context)

        #expect(mayas.isClosed)
        #expect(!elis.isClosed)
        let records = fixture.context.safeFetch(CDFetchRequest(CDWorkCompletionRecord.self))
        #expect(records.map(\.studentID) == [fixture.maya.uuidString])
        #expect(records.map(\.workID) == [try #require(mayas.id).uuidString])
    }

    @Test("Eli's work list shows his own copy once, not Maya's as well")
    func visibleWorkShowsOwnCopyOnly() throws {
        let fixture = try makeFixture()
        let works = try quickNewWork(fixture)
        let all = fixture.context.safeFetch(CDFetchRequest(CDWorkModel.self))
        let eliSees = WorkGrouping.visibleWork(for: fixture.eli, among: all, in: fixture.context)
        #expect(eliSees.map(\.objectID) == [works[1].objectID])
    }

    @Test("removing Eli from the work reaches both copies")
    func removalPlanCoversBothCopies() throws {
        let fixture = try makeFixture()
        let works = try quickNewWork(fixture)
        let plan = try WorkDeletionService(context: fixture.context).removalPlan(for: fixture.eli, from: works[0])
        #expect(Set(plan.steps.map(\.work.objectID)) == Set(works.map(\.objectID)))
    }

    // MARK: - Renamed copies

    @Test("a copy renamed on its own still groups with the others")
    func renamedCopyStaysLinked() throws {
        let fixture = try makeFixture()
        let works = try quickNewWork(fixture)
        works[1].title = "Commutative law — Eli's version"
        CoreDataTestHelpers.save(fixture.context)

        #expect(members(of: works[0], in: fixture.context) == Set(works.map(\.objectID)))
    }

    @Test("renaming in the work editor renames every linked copy, and the kind goes too")
    func editorRenameCarriesToLinkedCopies() throws {
        let fixture = try makeFixture()
        let works = try quickNewWork(fixture)
        let workID = try #require(works[0].id)
        let viewModel = WorkDetailViewModel(workID: workID)
        let saveCoordinator = SaveCoordinator()
        viewModel.loadWork(modelContext: fixture.context, saveCoordinator: saveCoordinator)

        viewModel.workTitle = "Write three examples"
        viewModel.workKind = .practiceLesson
        #expect(viewModel.save(modelContext: fixture.context, saveCoordinator: saveCoordinator))

        #expect(works.map(\.title) == ["Write three examples", "Write three examples"])
        #expect(works.map(\.kind) == [.practiceLesson, .practiceLesson])
        #expect(!fixture.context.hasChanges)
        #expect(members(of: works[1], in: fixture.context) == Set(works.map(\.objectID)))
    }

    // MARK: - What still stays apart

    @Test("two pieces of work given to the same children in the same minute stay two groups")
    func twoAssignmentsInOneMinuteStaySeparate() throws {
        let fixture = try makeFixture()
        let first = try quickNewWork(fixture, title: "Label the parts")
        let second = try quickNewWork(fixture, title: "Write a definition")

        for work in first {
            #expect(members(of: work, in: fixture.context) == Set(first.map(\.objectID)))
        }
        for work in second {
            #expect(members(of: work, in: fixture.context) == Set(second.map(\.objectID)))
        }
        // A status for everyone on the first reaches only the first.
        let rows = try WorkLogTargets.resolve(work: first[1], in: fixture.context)
        #expect(Set(rows.map(\.objectID)) == Set(first.map(\.objectID)))
    }

    @Test("in a minute with two assignments, a renamed copy still pairs with its own by creation time")
    func renamedCopyInABusyMinutePairsByTime() throws {
        let fixture = try makeFixture()
        let first = try quickNewWork(fixture, title: "Label the parts")
        let second = try quickNewWork(fixture, title: "Write a definition")
        let start = Date()
        first[0].createdAt = start
        first[1].createdAt = start.addingTimeInterval(0.002)
        second[0].createdAt = start.addingTimeInterval(20)
        second[1].createdAt = start.addingTimeInterval(20.002)
        first[1].title = "Eli's labels"
        CoreDataTestHelpers.save(fixture.context)

        #expect(members(of: first[0], in: fixture.context) == Set(first.map(\.objectID)))
        #expect(members(of: first[1], in: fixture.context) == Set(first.map(\.objectID)))
        #expect(members(of: second[0], in: fixture.context) == Set(second.map(\.objectID)))
    }

    @Test("project-session rows naming the same children are shared rows, not copies")
    func projectSessionRowsNeverLink() throws {
        let fixture = try makeFixture()
        let rows = try quickNewWork(fixture, title: "Read chapter 3")
        rows[1].title = "Draw the map"
        for row in rows { row.sourceContextType = .projectSession }
        CoreDataTestHelpers.save(fixture.context)

        #expect(!WorkGrouping.areLinkedCopies(rows[0], rows[1]))
        #expect(WorkGrouping.group(containing: rows[0], in: fixture.context).shape == .shared(childCount: 2))
    }

    @Test("rows with no creation date keep the old rule: different presentations stay apart")
    func undatedRowsKeepTheOldRule() throws {
        let fixture = try makeFixture()
        let works = try quickNewWork(fixture)
        for work in works { work.createdAt = nil }
        CoreDataTestHelpers.save(fixture.context)

        #expect(!WorkGrouping.areLinkedCopies(works[0], works[1]))

        works[1].presentationID = works[0].presentationID
        #expect(WorkGrouping.areLinkedCopies(works[0], works[1]))
        works[1].title = "Renamed"
        #expect(!WorkGrouping.areLinkedCopies(works[0], works[1]))
    }
}
