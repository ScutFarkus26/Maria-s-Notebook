import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The student page's progress views and the Class Grid's Children view, from the
/// 2026-11-03 bug hunt (S2): #26 the sequence sheet and the track timeline count shared
/// project work as the Children card does; #27 the sheet's Notes tab finds notes made on
/// a presentation, a work or a check-in; #28 a year-plan entry reads Planned there as on
/// the Checklist, and a mastery mark alone puts a sequence on her card; #29 the Progress
/// card's Next Lesson is the timeline's Next; #32 Plan Lesson makes no plan for a child
/// who has left.
@Suite("Progress, Children and Insights fixes 2026-11-03")
@MainActor
struct StudentProgressFix1103S2 {

    /// Maya Stone and Ben Kahn; Math › Chains 0–3.
    private struct Fixture {
        let stack: CoreDataStack
        let maya: CDStudent
        let ben: CDStudent
        let chains: [CDLesson]
        var context: NSManagedObjectContext { stack.viewContext }

        func mayaID() throws -> UUID { try #require(maya.id) }
        func benID() throws -> UUID { try #require(ben.id) }
        func lessonID(_ index: Int) throws -> UUID { try #require(chains[index].id) }

        func timeline() -> StudentAreaProgressionViewModel {
            let timeline = StudentAreaProgressionViewModel()
            timeline.configure(for: maya, area: "Math", sequence: "Chains", context: context)
            return timeline
        }

        func sheet() throws -> StudentSequenceDetail {
            StudentSequenceDetailLoader.load(
                target: StudentSequenceDetailTarget(
                    studentID: try mayaID(), studentName: "Maya S", area: "Math", sequence: "Chains",
                    lessonIDs: chains.compactMap(\.id)
                ),
                context: context
            )
        }

        func childrenCard(for student: CDStudent) -> StudentProgressionCard? {
            let model = ClassGridChildrenModel()
            model.loadData(context: context)
            return model.studentCards.first { $0.id == student.id }
        }
    }

    private func makeFixture(
        mayaStatus: CDStudent.EnrollmentStatus = .enrolled,
        seed: (Fixture) throws -> Void = { _ in }
    ) throws -> Fixture {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let maya = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Maya", lastName: "Stone", enrollmentStatus: mayaStatus
        )
        let ben = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben", lastName: "Kahn")
        let chains = (0..<4).map { index in
            let lesson = CoreDataTestHelpers.seedLesson(
                in: context, name: "Chain \(index)", area: "Math", sequence: "Chains"
            )
            lesson.orderInSequence = Int64(index)
            return lesson
        }
        let fixture = Fixture(stack: stack, maya: maya, ben: ben, chains: chains)
        try seed(fixture)
        try context.save()
        return fixture
    }

    // MARK: - #26 Shared project work

    @Test("#26: the sequence sheet and the timeline show shared project work she doesn't own")
    func sharedProjectWorkShows() throws {
        var shared: CDWorkModel?
        var classmatesCopy: CDWorkModel?
        var herCopy: CDWorkModel?
        let fixture = try makeFixture { fixture in
            let context = fixture.context
            _ = PresentationFactory.makePresented(
                lessonID: try fixture.lessonID(0), studentIDs: [try fixture.mayaID()], context: context
            )
            // A project row Ben owns, with Maya on it, on Chain 0.
            let row = CoreDataTestHelpers.seedWorkModel(
                in: context, title: "Chain project", studentID: try fixture.benID(), lessonID: try fixture.lessonID(0)
            )
            row.sourceContextType = .projectSession
            row.status = .active
            try participants([fixture.maya, fixture.ben], on: row, in: context)
            shared = row
            // Linked copies on Chain 1: hers closed, Ben's open and naming her.
            let copies = try linkedCopies(
                on: fixture.chains[1], statuses: [(fixture.maya, .done), (fixture.ben, .active)], in: context
            )
            herCopy = copies[0]
            classmatesCopy = copies[1]
        }

        let workIDs = Set(try fixture.sheet().work.map(\.id))
        #expect(workIDs.contains(try #require(shared?.id)))
        #expect(workIDs.contains(try #require(herCopy?.id)))
        #expect(!workIDs.contains(try #require(classmatesCopy?.id)))

        let nodes = fixture.timeline().nodes
        #expect(nodes[0].status == .practicing)
        #expect(nodes[0].activeWork.map(\.id) == [try #require(shared?.id)])
        #expect(nodes[1].status == .reviewing)
        #expect(nodes[1].activeWork.map(\.id) == [try #require(herCopy?.id)])
    }

    // MARK: - #27 Notes

    @Test("#27: the sheet's Notes tab shows notes made on her presentation, her work and its check-in")
    func linkedNotesShow() throws {
        let fixture = try makeFixture { fixture in
            let context = fixture.context
            let maya = try fixture.mayaID()
            let given = PresentationFactory.makePresented(
                lessonID: try fixture.lessonID(0), studentIDs: [maya], context: context
            )
            let onPresentation = CoreDataTestHelpers.seedNote(in: context, body: "Traced the chain carefully")
            onPresentation.scope = .student(maya)
            onPresentation.lessonAssignment = given

            let work = CoreDataTestHelpers.seedWorkModel(
                in: context, title: "Chain work", studentID: maya, lessonID: try fixture.lessonID(1)
            )
            let onWork = CoreDataTestHelpers.seedNote(in: context, body: "Counted to 100 alone")
            onWork.scope = .student(maya)
            onWork.work = work

            let checkIn = CDWorkCheckIn.make(for: work, on: Date(), in: context)
            let onCheckIn = CoreDataTestHelpers.seedNote(in: context, body: "Asked for the next chain")
            onCheckIn.scope = .student(maya)
            onCheckIn.workCheckIn = checkIn

            let onLesson = CoreDataTestHelpers.seedNote(in: context, body: "Whole class loved this")
            onLesson.lessonID = try fixture.lessonID(2).uuidString

            // Ben's presentation of the same lesson, and a note about him alone.
            let bens = PresentationFactory.makePresented(
                lessonID: try fixture.lessonID(0), studentIDs: [try fixture.benID()], context: context
            )
            let aboutBen = CoreDataTestHelpers.seedNote(in: context, body: "Ben skipped a bead")
            aboutBen.scope = .student(try fixture.benID())
            aboutBen.lessonAssignment = bens
        }

        let notes = try fixture.sheet().notes
        #expect(Set(notes.map(\.body)) == [
            "Traced the chain carefully", "Counted to 100 alone", "Asked for the next chain", "Whole class loved this"
        ])
        let byBody = Dictionary(notes.map { ($0.body, $0.lessonName) }, uniquingKeysWith: { first, _ in first })
        #expect(byBody["Traced the chain carefully"] == "Chain 0")
        #expect(byBody["Counted to 100 alone"] == "Chain 1")
        #expect(byBody["Asked for the next chain"] == "Chain 1")
    }

    // MARK: - #28 The year plan and mastery marks

    @Test("#28: a year-plan entry on the lesson she's up to reads Planned on her card and timeline")
    func yearPlanReadsPlanned() throws {
        let fixture = try makeFixture { fixture in
            let context = fixture.context
            _ = PresentationFactory.makePresented(
                lessonID: try fixture.lessonID(0), studentIDs: [try fixture.mayaID()], context: context
            )
            // Chain 1 is the one she's up to; Chain 3's entry still waits on Chain 2.
            try yearPlanEntry(fixture.maya, fixture.chains[1], in: context)
            try yearPlanEntry(fixture.maya, fixture.chains[3], in: context)
            // A skipped entry is no plan.
            try yearPlanEntry(fixture.ben, fixture.chains[0], status: .skipped, in: context)
        }

        let card = try #require(fixture.childrenCard(for: fixture.maya))
        let pills = try #require(card.subjects.first?.sequences.first?.pills)
        #expect(pills.map(\.status) == [.presented, .planned, .notReady, .notReady])

        // The timeline says Planned too, so it no longer offers Plan Lesson on Chain 1
        // (which scheduled it silently onto the entry's day): Chain 2 is next.
        let timeline = fixture.timeline()
        #expect(timeline.nodes.map(\.status.label) == ["Presented", "Planned", "Not Started", "Not Started"])
        #expect(timeline.nodes.map(\.isNext) == [false, false, true, false])
    }

    @Test("#28: a sequence where her only record is a mastery mark is on her Children card")
    func masteryMarkCountsAsActivity() throws {
        let fixture = try makeFixture { fixture in
            let mark = CDLessonPresentation(context: fixture.context)
            mark.studentID = try fixture.mayaID().uuidString
            mark.lessonID = try fixture.lessonID(0).uuidString
            mark.state = .proficient
            mark.masteredAt = Date()
        }

        let card = try #require(fixture.childrenCard(for: fixture.maya))
        let sequence = try #require(card.subjects.first?.sequences.first)
        #expect(sequence.sequence == "Chains")
        #expect(sequence.pills.first?.status == .mastered)
        #expect(fixture.childrenCard(for: fixture.ben) == nil)
    }

    // MARK: - #29 The Progress card's Next Lesson

    @Test("#29: the Progress card's Next Lesson is the timeline's Next, not a lesson she's practicing")
    func progressCardNextIsTheTimelinesNext() throws {
        let fixture = try makeFixture { fixture in
            let context = fixture.context
            let maya = try fixture.mayaID()
            // Chain 0 given, practice open; Chain 1 waiting in the Inbox.
            let given = PresentationFactory.makePresented(
                lessonID: try fixture.lessonID(0), studentIDs: [maya], context: context
            )
            let row = CDLessonPresentation(context: context)
            row.studentID = maya.uuidString
            row.lessonID = try fixture.lessonID(0).uuidString
            row.presentationID = given.id?.uuidString
            row.state = .presented
            row.presentedAt = given.presentedAt
            let practice = CoreDataTestHelpers.seedWorkModel(
                in: context, title: "Chain work", studentID: maya, lessonID: try fixture.lessonID(0)
            )
            practice.status = .active
            _ = PresentationFactory.makeDraft(lessonID: try fixture.lessonID(1), studentIDs: [maya], context: context)
        }

        let timelineNext = try #require(firstNext(in: fixture.timeline()))
        #expect(timelineNext.lesson.objectID == fixture.chains[2].objectID)

        let viewModel = StudentProgressTabViewModel()
        viewModel.configure(for: fixture.maya, context: fixture.context)
        let standing = try #require(viewModel.standings.first { $0.sequence == "Chains" })
        #expect(viewModel.nextLessonByStanding[standing.id]?.objectID == fixture.chains[2].objectID)
    }

    // MARK: - #32 A child who has left

    @Test("#32: Plan Lesson makes no plan for a child who has left the class")
    func planLessonRefusesADepartedChild() throws {
        let fixture = try makeFixture(mayaStatus: .withdrawn)
        let timeline = fixture.timeline()
        let next = try #require(firstNext(in: timeline))

        timeline.planLesson(next.lesson, context: fixture.context)

        let request = CDFetchRequest(CDLessonAssignment.self)
        #expect(try fixture.context.fetch(request).isEmpty)
    }
}

// MARK: - Seeding

private extension StudentProgressFix1103S2 {
    /// The timeline's Next lesson (kept out of `#require`, whose expansion can't take a closure).
    func firstNext(in timeline: StudentAreaProgressionViewModel) -> LessonProgressionNode? {
        timeline.nodes.first { $0.isNext }
    }

    func participants(_ children: [CDStudent], on row: CDWorkModel, in context: NSManagedObjectContext) throws {
        for child in children {
            let participant = CDWorkParticipantEntity(context: context)
            participant.id = UUID()
            participant.studentID = try #require(child.id).uuidString
            participant.work = row
        }
    }

    /// Linked copies on `lesson`: one row per child, each naming every child, made together.
    func linkedCopies(
        on lesson: CDLesson, statuses: [(CDStudent, WorkStatus)], in context: NSManagedObjectContext
    ) throws -> [CDWorkModel] {
        let made = Date()
        let lessonID = try #require(lesson.id)
        let children = statuses.map(\.0)
        return try statuses.map { owner, status in
            let row = CoreDataTestHelpers.seedWorkModel(
                in: context, title: lesson.name, studentID: try #require(owner.id), lessonID: lessonID
            )
            row.status = status
            row.createdAt = made
            try participants(children, on: row, in: context)
            return row
        }
    }

    @discardableResult
    func yearPlanEntry(
        _ student: CDStudent, _ lesson: CDLesson, status: YearPlanEntryStatus = .planned,
        in context: NSManagedObjectContext
    ) throws -> CDYearPlanEntry {
        let entry = CDYearPlanEntry(context: context)
        entry.studentID = try #require(student.id).uuidString
        entry.lessonID = try #require(lesson.id).uuidString
        entry.plannedDate = AppCalendar.startOfDay(Date()).addingTimeInterval(7 * 86_400)
        entry.status = status
        return entry
    }
}
