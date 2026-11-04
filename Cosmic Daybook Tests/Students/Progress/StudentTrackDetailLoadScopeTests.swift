import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Pins what opening one student's sequence detail materialises: the sheet's
/// own load (`StudentTrackDetailLoader`, a fresh `SequenceStanding`) plus the
/// timeline it hands to `StudentAreaProgressionViewModel`. Each read is scoped
/// to the sequence's lessons and to the child. The sheet's output, and the
/// lesson it plans, must not change. (Since 2026-10-10 the timeline reads
/// mastery from the mark and plans the lesson tapped; since 2026-11-03 the
/// sheet opens on a standing, not a track enrollment.)
@Suite("Student Track Detail load scope")
@MainActor
struct StudentTrackDetailLoadScopeTests {

    enum Store {
        case inMemory, sqlite
    }

    private struct Seeded {
        let context: NSManagedObjectContext
        let owner: AnyObject?
        let student: CDStudent
        let firstLesson: CDLesson
        let secondLesson: CDLesson
    }

    /// One student on "Math — Chains" (two lessons: the first mastered,
    /// presented and carrying open work with a completed check-in), next to
    /// `others` classmates who each carry the same shape on a sequence of
    /// their own.
    private func seed(others: Int, store: Store = .inMemory) throws -> Seeded {
        let context: NSManagedObjectContext
        let owner: AnyObject?
        switch store {
        case .inMemory:
            let stack = try CoreDataTestHelpers.makeInMemoryStack()
            context = stack.viewContext
            owner = stack
        case .sqlite:
            context = try CoreDataTestHelpers.makeSplitStoreContext()
            owner = nil
        }

        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "S")
        let first = CoreDataTestHelpers.seedLesson(in: context, name: "Bead Chains", area: "Math", sequence: "Chains")
        first.orderInSequence = 0
        let second = CoreDataTestHelpers.seedLesson(in: context, name: "Bead Squares", area: "Math", sequence: "Chains")
        second.orderInSequence = 1
        seedStanding(for: student, lessons: [first, second], in: context)
        for index in 0..<others {
            let other = CoreDataTestHelpers.seedStudent(in: context, firstName: "Other", lastName: "\(index)")
            let lesson = CoreDataTestHelpers.seedLesson(
                in: context, name: "Lesson \(index)", area: "Language", sequence: "Seq \(index)"
            )
            seedStanding(for: other, lessons: [lesson], in: context)
        }

        let studentUUID = try #require(student.id)
        let firstUUID = try #require(first.id)
        let secondUUID = try #require(second.id)
        try context.save()
        context.reset()

        return Seeded(
            context: context, owner: owner,
            student: try #require(context.object(CDStudent.self, id: studentUUID)),
            firstLesson: try #require(context.object(CDLesson.self, id: firstUUID)),
            secondLesson: try #require(context.object(CDLesson.self, id: secondUUID))
        )
    }

    /// The first lesson mastered, presented, and carrying open work with one
    /// completed check-in.
    private func seedStanding(for student: CDStudent, lessons: [CDLesson], in context: NSManagedObjectContext) {
        let studentID = student.id?.uuidString ?? ""
        let first = lessons[0]
        let firstID = first.id?.uuidString ?? ""

        let mark = CDLessonPresentation(context: context)
        mark.studentID = studentID
        mark.lessonID = firstID
        mark.state = .proficient
        mark.presentedAt = Date()

        let assignment = CDLessonAssignment(context: context)
        assignment.lessonID = firstID
        assignment.studentIDs = [studentID]
        assignment.state = .presented
        assignment.presentedAt = Date()

        let work = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "Chain work", studentID: student.id ?? UUID(), lessonID: first.id ?? UUID()
        )
        _ = CDWorkCheckIn.make(for: work, on: Date(), status: .completed, in: context)
    }

    @Test(
        "The sheet finds the sequence's lessons, her marks and her timeline among classmates",
        arguments: [Store.inMemory, .sqlite]
    )
    func outputsAreScopedToTheStudent(store: Store) throws {
        let seeded = try seed(others: 12, store: store)
        defer { withExtendedLifetime(seeded.owner) {} }
        let firstID = try #require(seeded.firstLesson.id).uuidString

        let load = StudentTrackDetailLoader.load(
            student: seeded.student, area: "Math", sequence: "Chains", context: seeded.context
        )
        #expect(load.standing.title == "Math — Chains")
        #expect(load.trackLessons.map(\.objectID) == [seeded.firstLesson.objectID, seeded.secondLesson.objectID])
        #expect(load.presentedLessonIDs == [firstID])
        #expect(load.proficientLessonIDs == [firstID])
        #expect(load.standing.isInProgress)
        #expect(load.standing.nextLesson?.objectID == seeded.secondLesson.objectID)

        let timeline = StudentAreaProgressionViewModel()
        timeline.configure(for: seeded.student, area: "Math", sequence: "Chains", context: seeded.context)
        #expect(timeline.totalCount == 2)
        // The first lesson's mastery mark makes it Mastered, open work or not (the Checklist's rule).
        #expect(timeline.completedCount == 1)
        #expect(timeline.nodes.map(\.id) == [seeded.firstLesson.id, seeded.secondLesson.id])
        let first = try #require(timeline.nodes.first)
        #expect(first.status == .mastered)
        #expect(first.activeWork.count == 1)
        #expect(first.activeWork.first?.lastCheckIn != nil)
        #expect(first.isNext == false)
        let second = try #require(timeline.nodes.last)
        guard case .notStarted = second.status else {
            Issue.record("second lesson should not be started, was \(second.status)")
            return
        }
        #expect(second.isNext)
    }

    @Test("Planning the next lesson drafts it once and then sees the draft")
    func scheduleNextLessonSeesTheDraftItMade() throws {
        let seeded = try seed(others: 12)
        defer { withExtendedLifetime(seeded.owner) {} }
        let secondID = try #require(seeded.secondLesson.id)
        let studentID = try #require(seeded.student.id)

        let timeline = StudentAreaProgressionViewModel()
        timeline.configure(for: seeded.student, area: "Math", sequence: "Chains", context: seeded.context)
        timeline.planLesson(seeded.secondLesson, context: seeded.context)
        timeline.configure(for: seeded.student, area: "Math", sequence: "Chains", context: seeded.context)
        timeline.planLesson(seeded.secondLesson, context: seeded.context)

        let drafts = CDFetchRequest(CDLessonAssignment.self)
        drafts.predicate = NSPredicate(format: "lessonID == %@", secondID.uuidString)
        let made = try seeded.context.fetch(drafts)
        #expect(made.count == 1)
        #expect(made.first?.state == .draft)
        #expect(made.first?.resolvedStudentIDs == [studentID])
    }

    @Test("Opening one student's sequence materialises her rows, not the classroom's")
    func loadMaterialisesOnlyTheStudentsRows() throws {
        let seeded = try seed(others: 12)
        defer { withExtendedLifetime(seeded.owner) {} }
        let before = seeded.context.registeredObjects.count

        let load = StudentTrackDetailLoader.load(
            student: seeded.student, area: "Math", sequence: "Chains", context: seeded.context
        )
        let timeline = StudentAreaProgressionViewModel()
        timeline.configure(
            for: seeded.student, area: load.standing.area, sequence: load.standing.sequence, context: seeded.context
        )

        let registered = seeded.context.registeredObjects.count - before
        // Her mark, her presented assignment, her work and its check-in: 4.
        // The student and both lessons were registered before the count.
        // The whole-table load registered 76 (2026-09-21).
        #expect(registered <= 6, "registered \(registered) objects for one student")
    }
}
