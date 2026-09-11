import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

// A migration that ran twice on 2026-01-10 defined 22 sequence tracks a
// second time under fresh ids. The merge keeps the older record, moves the
// steps and enrollments onto it, repoints every id string, and the runtime
// lookup prefers the twin with steps until the merge has run everywhere.

@Suite("Track Title Merge")
@MainActor
struct TrackTitleMergeTests {

    private func makeContext() throws -> NSManagedObjectContext {
        try CoreDataTestHelpers.makeInMemoryStack().viewContext
    }

    private func day(_ text: String) throws -> Date {
        try #require(MCPNotebookTools.isoDay.date(from: text))
    }

    @discardableResult
    private func seedTrack(
        _ title: String, createdAt: Date, lessons: [CDLesson], in context: NSManagedObjectContext
    ) -> CDTrackEntity {
        let track = CDTrackEntity(context: context)
        track.title = title
        track.createdAt = createdAt
        for (index, lesson) in lessons.enumerated() {
            let step = CDTrackStepEntity(context: context)
            step.orderIndex = Int64(index)
            step.lessonTemplateID = lesson.id
            step.track = track
        }
        return track
    }

    @discardableResult
    private func enroll(
        _ student: CDStudent, on track: CDTrackEntity, active: Bool = true, startedAt: Date? = nil,
        in context: NSManagedObjectContext
    ) -> CDStudentTrackEnrollmentEntity {
        let enrollment = CDStudentTrackEnrollmentEntity(context: context)
        enrollment.studentID = student.id?.uuidString ?? ""
        enrollment.trackID = track.id?.uuidString ?? ""
        enrollment.track = track
        enrollment.student = student
        enrollment.isActive = active
        enrollment.startedAt = startedAt
        return enrollment
    }

    private func seedAssignment(
        _ lesson: CDLesson, for student: CDStudent, track: String, step: String, in context: NSManagedObjectContext
    ) -> CDLessonAssignment {
        let assignment = CDLessonAssignment(context: context)
        assignment.lessonID = lesson.id?.uuidString ?? ""
        assignment.studentIDs = [student.id?.uuidString ?? ""]
        assignment.trackID = track
        assignment.trackStepID = step
        return assignment
    }

    private func seedMark(
        _ lesson: CDLesson, for student: CDStudent, track: String, step: String, in context: NSManagedObjectContext
    ) -> CDLessonPresentation {
        let mark = CDLessonPresentation(context: context)
        mark.studentID = student.id?.uuidString ?? ""
        mark.lessonID = lesson.id?.uuidString ?? ""
        mark.trackID = track
        mark.trackStepID = step
        return mark
    }

    private func tracks(in context: NSManagedObjectContext) -> [CDTrackEntity] {
        context.safeFetch(CDFetchRequest(CDTrackEntity.self)).filter { !$0.isDeleted }
    }

    // MARK: - Detection

    @Test("Same title folded for case and whitespace is a duplicate; other titles are not")
    func detectsSameTitleOnly() throws {
        let context = try makeContext()
        seedTrack("Math — Laws", createdAt: try day("2026-01-10"), lessons: [], in: context)
        seedTrack("math — laws ", createdAt: try day("2026-01-10"), lessons: [], in: context)
        seedTrack("Math — Fractions", createdAt: try day("2026-01-10"), lessons: [], in: context)
        CoreDataTestHelpers.save(context)

        let groups = DataCleanupService.sameTitleTrackGroups(using: context)
        #expect(groups.count == 1)
        #expect(Set(groups.first?.map(\.title) ?? []) == ["Math — Laws", "math — laws "])
    }

    // MARK: - Merge

    @Test("Merge keeps the older twin, moves the steps, and repoints presentations, marks and work")
    func mergeMovesStepsAndRepoints() throws {
        let context = try makeContext()
        let commutative = CoreDataTestHelpers.seedLesson(
            in: context, name: "Commutative Law", area: "Math", sequence: "Laws"
        )
        let distributive = CoreDataTestHelpers.seedLesson(
            in: context, name: "Distributive Law", area: "Math", sequence: "Laws"
        )
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Avital", lastName: "Beyderman")
        CoreDataTestHelpers.save(context)

        // The older twin is the empty shell; the newer one carries the steps.
        let older = seedTrack(
            "Math — Laws", createdAt: try day("2026-01-10"), lessons: [commutative], in: context
        )
        let newer = seedTrack(
            "Math — Laws", createdAt: try day("2026-01-10").addingTimeInterval(300),
            lessons: [commutative, distributive], in: context
        )
        CoreDataTestHelpers.save(context)
        let olderID = try #require(older.id).uuidString
        let newerID = try #require(newer.id).uuidString
        let newerSteps = try #require(newer.steps?.allObjects as? [CDTrackStepEntity])
            .sorted { $0.orderIndex < $1.orderIndex }
        let duplicateCommutativeStep = try #require(newerSteps.first?.id).uuidString
        let distributiveStep = try #require(newerSteps.last?.id).uuidString
        let olderSteps = older.steps?.allObjects as? [CDTrackStepEntity]
        let keptCommutativeStep = try #require(olderSteps?.first?.id).uuidString

        let assignment = seedAssignment(commutative, for: student, track: newerID, step: duplicateCommutativeStep,
                                        in: context)
        let mark = seedMark(distributive, for: student, track: newerID, step: distributiveStep, in: context)
        let work = CoreDataTestHelpers.seedWorkModel(
            in: context, studentID: try #require(student.id), lessonID: try #require(commutative.id)
        )
        work.trackID = newerID
        work.trackStepID = duplicateCommutativeStep
        CoreDataTestHelpers.save(context)

        let removed = DataCleanupService.mergeSameTitleTracks(using: context)
        #expect(CoreDataTestHelpers.save(context))
        #expect(removed == 1)

        let survivors = tracks(in: context)
        #expect(survivors.map { $0.id?.uuidString } == [olderID])
        let steps = try #require(survivors.first?.steps?.allObjects as? [CDTrackStepEntity])
        let stepLessons = Set(steps.compactMap(\.lessonTemplateID))
        #expect(steps.count == 2 && stepLessons == Set([commutative.id, distributive.id].compactMap { $0 }))

        #expect(assignment.trackID == olderID)
        #expect(assignment.trackStepID == keptCommutativeStep)
        #expect(mark.trackID == olderID)
        #expect(mark.trackStepID == distributiveStep)
        #expect(work.trackID == olderID)
        #expect(work.trackStepID == keptCommutativeStep)

        // Idempotent: a second pass finds nothing.
        #expect(DataCleanupService.mergeSameTitleTracks(using: context) == 0)
    }

    @Test("A child enrolled on both twins keeps one enrollment, the active one, and her notes follow it")
    func mergeCollapsesEnrollments() throws {
        let context = try makeContext()
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Simma", lastName: "Katz")
        let peer = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(context)
        let older = seedTrack("Math — Laws", createdAt: try day("2026-01-10"), lessons: [], in: context)
        let newer = seedTrack(
            "Math — Laws", createdAt: try day("2026-01-10").addingTimeInterval(300), lessons: [], in: context
        )
        CoreDataTestHelpers.save(context)

        let retired = enroll(student, on: older, active: false, startedAt: try day("2026-01-11"), in: context)
        let live = enroll(student, on: newer, active: true, startedAt: try day("2026-02-01"), in: context)
        enroll(peer, on: newer, in: context)
        let note = CoreDataTestHelpers.seedNote(in: context, body: "Working steadily through the laws.")
        note.studentTrackEnrollmentID = retired.id?.uuidString
        CoreDataTestHelpers.save(context)

        DataCleanupService.mergeSameTitleTracks(using: context)
        #expect(CoreDataTestHelpers.save(context))

        let enrollments = context.safeFetch(CDFetchRequest(CDStudentTrackEnrollmentEntity.self))
            .filter { !$0.isDeleted }
        #expect(enrollments.count == 2)
        let hers = enrollments.filter { $0.studentID == student.id?.uuidString }
        #expect(hers.count == 1)
        #expect(hers.first?.id == live.id)
        #expect(hers.first?.trackID == older.id?.uuidString)
        #expect(hers.first?.track === older)
        #expect(note.studentTrackEnrollmentID == live.id?.uuidString)
        #expect(retired.managedObjectContext == nil)
    }

    @Test("Survivor is the older record by createdAt, whichever twin carries the steps")
    func survivorIsOlder() throws {
        let context = try makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Bells", area: "Music", sequence: "Tone Bars")
        CoreDataTestHelpers.save(context)
        let newerWithSteps = seedTrack(
            "Music — Tone Bars", createdAt: try day("2026-03-01"), lessons: [lesson], in: context
        )
        let olderShell = seedTrack("Music — Tone Bars", createdAt: try day("2026-01-10"), lessons: [], in: context)
        CoreDataTestHelpers.save(context)

        #expect(DataCleanupService.olderTrackPrecedes(olderShell, newerWithSteps, container: nil))
        DataCleanupService.mergeSameTitleTracks(using: context)
        #expect(CoreDataTestHelpers.save(context))
        let survivors = tracks(in: context)
        #expect(survivors.first?.id == olderShell.id)
        #expect(survivors.first?.steps?.count == 1)
        #expect(newerWithSteps.managedObjectContext == nil)
    }

    // MARK: - Runtime lookup

    @Test("getOrCreateTrack lands on the twin with steps and never creates a third")
    func lookupPrefersSteppedTwin() throws {
        let context = try makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Bells", area: "Music", sequence: "Tone Bars")
        CoreDataTestHelpers.save(context)
        seedTrack("Music — Tone Bars", createdAt: try day("2026-01-10"), lessons: [], in: context)
        let stepped = seedTrack("Music — Tone Bars", createdAt: try day("2026-03-01"), lessons: [lesson], in: context)
        CoreDataTestHelpers.save(context)

        let found = try SequenceTrackService.getOrCreateTrack(area: "Music", sequence: "Tone Bars", context: context)
        #expect(found.id == stepped.id)
        #expect(tracks(in: context).count == 2)
        let again = try SequenceTrackService.cdGetTrack(area: "Music", sequence: "Tone Bars", context: context)
        #expect(again?.id == stepped.id)
    }
}
