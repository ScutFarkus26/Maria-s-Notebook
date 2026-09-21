import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Pins what opening one student's track detail materialises: the sheet's
/// own load (`StudentTrackDetailLoader`) plus the timeline it hands to
/// `StudentAreaProgressionViewModel`. Before 2026-09-21 the pair read every
/// student, lesson, mark, assignment, work row and check-in; now each read is
/// scoped to the track's area and sequence and to the child. The sheet's
/// output, and the next lesson it schedules, must not change.
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
        let track: CDTrackEntity
        let enrollment: CDStudentTrackEnrollmentEntity
        let firstLesson: CDLesson
        let secondLesson: CDLesson
    }

    /// One student on "Math — Chains" (two lessons: the first mastered,
    /// presented and carrying open work with a completed check-in), next to
    /// `others` classmates who each carry the same shape on their own track.
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
        let (track, enrollment) = seedTrack(
            title: "Math — Chains", for: student, lessons: [first, second], in: context
        )
        for index in 0..<others {
            let other = CoreDataTestHelpers.seedStudent(in: context, firstName: "Other", lastName: "\(index)")
            let lesson = CoreDataTestHelpers.seedLesson(
                in: context, name: "Lesson \(index)", area: "Language", sequence: "Seq \(index)"
            )
            _ = seedTrack(title: "Language — Seq \(index)", for: other, lessons: [lesson], in: context)
        }

        let studentUUID = try #require(student.id)
        let trackUUID = try #require(track.id)
        let enrollmentUUID = try #require(enrollment.id)
        let firstUUID = try #require(first.id)
        let secondUUID = try #require(second.id)
        try context.save()
        context.reset()

        return Seeded(
            context: context, owner: owner,
            student: try #require(context.object(CDStudent.self, id: studentUUID)),
            track: try #require(context.object(CDTrackEntity.self, id: trackUUID)),
            enrollment: try #require(context.object(CDStudentTrackEnrollmentEntity.self, id: enrollmentUUID)),
            firstLesson: try #require(context.object(CDLesson.self, id: firstUUID)),
            secondLesson: try #require(context.object(CDLesson.self, id: secondUUID))
        )
    }

    /// A track for `lessons`, the student enrolled and active, the first
    /// lesson mastered, presented, and carrying open work with one completed
    /// check-in.
    private func seedTrack(
        title: String, for student: CDStudent, lessons: [CDLesson], in context: NSManagedObjectContext
    ) -> (CDTrackEntity, CDStudentTrackEnrollmentEntity) {
        let studentID = student.id?.uuidString ?? ""
        let first = lessons[0]
        let firstID = first.id?.uuidString ?? ""
        let track = CDTrackEntity(context: context)
        track.title = title
        let enrollment = CDStudentTrackEnrollmentEntity(context: context)
        enrollment.studentID = studentID
        enrollment.trackID = track.id?.uuidString ?? ""
        enrollment.track = track
        enrollment.student = student
        enrollment.isActive = true

        let mark = CDLessonPresentation(context: context)
        mark.studentID = studentID
        mark.lessonID = firstID
        mark.state = .proficient

        let assignment = CDLessonAssignment(context: context)
        assignment.lessonID = firstID
        assignment.studentIDs = [studentID]
        assignment.state = .presented
        assignment.presentedAt = Date()

        let work = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "Chain work", studentID: student.id ?? UUID(), lessonID: first.id ?? UUID()
        )
        _ = CDWorkCheckIn.make(for: work, on: Date(), status: .completed, in: context)
        return (track, enrollment)
    }

    @Test(
        "The sheet finds the child, the track's lessons, her marks and her timeline among classmates",
        arguments: [Store.inMemory, .sqlite]
    )
    func outputsAreScopedToTheStudent(store: Store) throws {
        let seeded = try seed(others: 12, store: store)
        defer { withExtendedLifetime(seeded.owner) {} }
        let firstID = try #require(seeded.firstLesson.id).uuidString

        let load = StudentTrackDetailLoader.load(
            enrollment: seeded.enrollment, track: seeded.track, context: seeded.context
        )
        #expect(load.area == "Math")
        #expect(load.sequence == "Chains")
        #expect(load.student?.objectID == seeded.student.objectID)
        #expect(load.trackLessons.map(\.objectID) == [seeded.firstLesson.objectID, seeded.secondLesson.objectID])
        #expect(load.presentedLessonIDs == [firstID])
        #expect(load.proficientLessonIDs == [firstID])

        let timeline = StudentAreaProgressionViewModel()
        timeline.configure(for: seeded.student, area: load.area, sequence: load.sequence, context: seeded.context)
        #expect(timeline.totalCount == 2)
        #expect(timeline.completedCount == 0)
        #expect(timeline.nodes.map(\.id) == [seeded.firstLesson.id, seeded.secondLesson.id])
        let first = try #require(timeline.nodes.first)
        guard case .practicing = first.status else {
            Issue.record("first lesson should be practicing, was \(first.status)")
            return
        }
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

    @Test("Scheduling the next lesson still drafts it once and then sees the draft")
    func scheduleNextLessonSeesTheDraftItMade() throws {
        let seeded = try seed(others: 12)
        defer { withExtendedLifetime(seeded.owner) {} }
        let secondID = try #require(seeded.secondLesson.id)
        let studentID = try #require(seeded.student.id)

        let timeline = StudentAreaProgressionViewModel()
        timeline.configure(for: seeded.student, area: "Math", sequence: "Chains", context: seeded.context)
        timeline.scheduleNextLesson(after: seeded.firstLesson, context: seeded.context)
        timeline.configure(for: seeded.student, area: "Math", sequence: "Chains", context: seeded.context)
        timeline.scheduleNextLesson(after: seeded.firstLesson, context: seeded.context)

        let drafts = CDFetchRequest(CDLessonAssignment.self)
        drafts.predicate = NSPredicate(format: "lessonID == %@", secondID.uuidString)
        let made = try seeded.context.fetch(drafts)
        #expect(made.count == 1)
        #expect(made.first?.state == .draft)
        #expect(made.first?.resolvedStudentIDs == [studentID])
    }

    @Test("Opening one student's track materialises her rows, not the classroom's")
    func loadMaterialisesOnlyTheStudentsRows() throws {
        let seeded = try seed(others: 12)
        defer { withExtendedLifetime(seeded.owner) {} }
        let before = seeded.context.registeredObjects.count

        let load = StudentTrackDetailLoader.load(
            enrollment: seeded.enrollment, track: seeded.track, context: seeded.context
        )
        let timeline = StudentAreaProgressionViewModel()
        timeline.configure(for: seeded.student, area: load.area, sequence: load.sequence, context: seeded.context)

        let registered = seeded.context.registeredObjects.count - before
        // Her mark, her presented assignment, her work and its check-in: 4.
        // The student, track, enrollment and both lessons were registered
        // before the count. The whole-table load registered 76 (2026-09-21).
        #expect(registered <= 6, "registered \(registered) objects for one student")
    }
}
