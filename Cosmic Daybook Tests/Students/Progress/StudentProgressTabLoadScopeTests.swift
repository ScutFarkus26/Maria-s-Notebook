import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Pins what `StudentProgressTabViewModel.loadData` materialises for one
/// student. Before 2026-09-18 it fetched eight whole tables and filtered in
/// memory; now each fetch is scoped to the student, so a classroom's worth
/// of other students' rows never leaves the store. The output for the
/// student must not change.
@Suite("Student Progress Tab load scope")
@MainActor
struct StudentProgressTabLoadScopeTests {

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
        let report: CDWorkModel
    }

    /// One student with one active track (two steps, first mastered), one
    /// track note, one open report and one project, next to `others`
    /// classmates who each carry the same shape of data on other tracks.
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
        let studentID = try #require(student.id).uuidString
        let first = CoreDataTestHelpers.seedLesson(in: context, name: "Bead Chains", area: "Math", sequence: "Chains")
        let second = CoreDataTestHelpers.seedLesson(in: context, name: "Bead Squares", area: "Math", sequence: "Chains")

        let (track, enrollment) = seedChainsTrack(for: student, lessons: [first, second], in: context)

        let note = CoreDataTestHelpers.seedNote(in: context, body: "Working steadily on chains")
        note.studentTrackEnrollment = enrollment

        let studentUUIDForWork = try #require(student.id)
        let secondUUIDForWork = try #require(second.id)
        let report = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "", studentID: studentUUIDForWork, lessonID: secondUUIDForWork
        )
        report.kind = .report
        report.trackID = enrollment.trackID

        let project = CDProject(context: context)
        project.title = "Bridges"
        project.memberStudentIDsArray = [studentID]

        seedClassmates(others, in: context)

        let studentUUID = try #require(student.id)
        let trackUUID = try #require(track.id)
        let enrollmentUUID = try #require(enrollment.id)
        let firstUUID = try #require(first.id)
        let secondUUID = try #require(second.id)
        let reportUUID = try #require(report.id)
        try context.save()
        context.reset()

        let reloadedStudent = try #require(context.object(CDStudent.self, id: studentUUID))
        let reloadedTrack = try #require(context.object(CDTrackEntity.self, id: trackUUID))
        let reloadedEnrollment = try #require(context.object(CDStudentTrackEnrollmentEntity.self, id: enrollmentUUID))
        let reloadedFirst = try #require(context.object(CDLesson.self, id: firstUUID))
        let reloadedSecond = try #require(context.object(CDLesson.self, id: secondUUID))
        let reloadedReport = try #require(context.object(CDWorkModel.self, id: reportUUID))
        return Seeded(
            context: context, owner: owner, student: reloadedStudent, track: reloadedTrack,
            enrollment: reloadedEnrollment, firstLesson: reloadedFirst, secondLesson: reloadedSecond,
            report: reloadedReport
        )
    }

    /// The student's active "Math — Chains" track: one step per lesson, the
    /// first lesson mastered and presented.
    private func seedChainsTrack(
        for student: CDStudent, lessons: [CDLesson], in context: NSManagedObjectContext
    ) -> (CDTrackEntity, CDStudentTrackEnrollmentEntity) {
        let studentID = student.id?.uuidString ?? ""
        let first = lessons[0]
        let track = CDTrackEntity(context: context)
        track.title = "Math — Chains"
        for (index, lesson) in lessons.enumerated() {
            let step = CDTrackStep(context: context)
            step.orderIndex = Int64(index)
            step.lessonTemplateID = lesson.id
            step.track = track
        }
        let enrollment = CDStudentTrackEnrollmentEntity(context: context)
        enrollment.studentID = studentID
        enrollment.trackID = track.id?.uuidString ?? ""
        enrollment.track = track
        enrollment.student = student
        enrollment.isActive = true

        let mark = CDLessonPresentation(context: context)
        mark.studentID = studentID
        mark.lessonID = first.id?.uuidString ?? ""
        mark.trackID = enrollment.trackID
        mark.state = .proficient

        let assignment = CDLessonAssignment(context: context)
        assignment.lessonID = first.id?.uuidString ?? ""
        assignment.studentIDs = [studentID]
        assignment.trackID = enrollment.trackID
        assignment.state = .presented
        assignment.presentedAt = Date()

        return (track, enrollment)
    }

    /// `count` classmates, each on their own track with a mark, an
    /// assignment, a track note, a report and a project.
    private func seedClassmates(_ count: Int, in context: NSManagedObjectContext) {
        for index in 0..<count {
            let other = CoreDataTestHelpers.seedStudent(in: context, firstName: "Other", lastName: "\(index)")
            let otherID = other.id?.uuidString ?? ""
            let lesson = CoreDataTestHelpers.seedLesson(
                in: context, name: "Lesson \(index)", area: "Language", sequence: "Seq \(index)"
            )
            let otherTrack = CDTrackEntity(context: context)
            otherTrack.title = "Language — Seq \(index)"
            let step = CDTrackStep(context: context)
            step.lessonTemplateID = lesson.id
            step.track = otherTrack
            let otherEnrollment = CDStudentTrackEnrollmentEntity(context: context)
            otherEnrollment.studentID = otherID
            otherEnrollment.trackID = otherTrack.id?.uuidString ?? ""
            otherEnrollment.track = otherTrack
            otherEnrollment.student = other
            otherEnrollment.isActive = true
            let otherMark = CDLessonPresentation(context: context)
            otherMark.studentID = otherID
            otherMark.lessonID = lesson.id?.uuidString ?? ""
            let otherAssignment = CDLessonAssignment(context: context)
            otherAssignment.lessonID = lesson.id?.uuidString ?? ""
            otherAssignment.studentIDs = [otherID]
            otherAssignment.trackID = otherEnrollment.trackID
            otherAssignment.state = .presented
            let otherNote = CoreDataTestHelpers.seedNote(in: context, body: "Other \(index)")
            otherNote.studentTrackEnrollment = otherEnrollment
            let otherWork = CoreDataTestHelpers.seedWorkModel(
                in: context, title: "Work \(index)", studentID: other.id ?? UUID(), lessonID: lesson.id ?? UUID()
            )
            otherWork.kind = .report
            let otherProject = CDProject(context: context)
            otherProject.title = "Project \(index)"
            otherProject.memberStudentIDsArray = [otherID]
        }
    }

    @Test(
        "The student's enrollments, stats, progress, report and project are found among classmates",
        arguments: [Store.inMemory, .sqlite]
    )
    func outputsAreScopedToTheStudent(store: Store) throws {
        let seeded = try seed(others: 12, store: store)
        defer { withExtendedLifetime(seeded.owner) {} }
        let viewModel = StudentProgressTabViewModel()
        viewModel.configure(for: seeded.student, context: seeded.context)

        #expect(viewModel.activeEnrollments.map(\.objectID) == [seeded.enrollment.objectID])
        #expect(viewModel.tracksByID[seeded.enrollment.trackID]?.objectID == seeded.track.objectID)
        #expect(viewModel.activeProjects.map(\.title) == ["Bridges"])
        #expect(viewModel.activeReports.map(\.objectID) == [seeded.report.objectID])
        #expect(viewModel.reportTitle(for: seeded.report) == "Bead Squares")

        let entry = try #require(seeded.enrollment.id.flatMap { viewModel.statsByEnrollment[$0] })
        #expect(entry.stats.presentationCount == 1)
        #expect(entry.stats.workCount == 1)
        #expect(entry.stats.noteCount == 1)
        #expect(entry.stats.totalActivity == 3)
        #expect(entry.progress.totalSteps == 2)
        #expect(entry.progress.proficientCount == 1)
        #expect(entry.progress.currentLesson?.objectID == seeded.secondLesson.objectID)
        #expect(entry.progress.isComplete == false)
    }

    @Test("Loading one student materialises that student's rows, not the classroom's")
    func loadMaterialisesOnlyTheStudentsRows() throws {
        let seeded = try seed(others: 12)
        let before = seeded.context.registeredObjects.count
        let viewModel = StudentProgressTabViewModel()
        viewModel.configure(for: seeded.student, context: seeded.context)
        let registered = seeded.context.registeredObjects.count - before
        // Track, 2 steps, enrollment, mark, assignment, note, report, next
        // lesson, plus every active project (the roster is a Transformable
        // blob, so projects cannot be scoped in the store): 18 here.
        // The whole-table load registered 114 (2026-09-18 baseline).
        #expect(registered <= 20, "registered \(registered) objects for one student")
    }
}
