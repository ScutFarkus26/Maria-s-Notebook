import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Pins what `SequenceTrackService` materialises when it enrols a student
/// and checks a track for completion. Before 2026-09-18 every call read the
/// whole lesson, step, presentation, enrollment and student tables; now each
/// read is scoped to the sequence, the track or the student. The records it
/// writes must not change.
@Suite("Sequence Track Service scope")
@MainActor
struct SequenceTrackServiceScopeTests {

    enum Store {
        case inMemory, sqlite
    }

    private struct Seeded {
        let context: NSManagedObjectContext
        let owner: AnyObject?
        let studentID: String
        let chainLessonIDs: [String]
    }

    /// Three sequences of `perSequence` lessons, `students` students who have
    /// each mastered the first lesson of every sequence, and a track already
    /// defined for Math — Chains.
    private func seed(perSequence: Int, students: Int, store: Store = .inMemory) throws -> Seeded {
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

        var chainLessonIDs: [String] = []
        var firstLessonIDs: [String] = []
        for (area, sequence) in [("Math", "Chains"), ("Math", "Fractions"), ("Language", "Grammar")] {
            for index in 0..<perSequence {
                let lesson = CoreDataTestHelpers.seedLesson(
                    in: context, name: "\(sequence) \(index)", area: area, sequence: sequence
                )
                lesson.orderInSequence = Int64(index)
                let id = lesson.id?.uuidString ?? ""
                if sequence == "Chains" { chainLessonIDs.append(id) }
                if index == 0 { firstLessonIDs.append(id) }
            }
        }

        var ids: [String] = []
        for index in 0..<students {
            let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Student", lastName: "\(index)")
            let id = student.id?.uuidString ?? ""
            ids.append(id)
            for lessonID in firstLessonIDs {
                let mark = CDLessonPresentation(context: context)
                mark.studentID = id
                mark.lessonID = lessonID
                mark.state = .proficient
            }
        }
        try context.save()

        _ = try SequenceTrackService.getOrCreateTrack(area: "Math", sequence: "Chains", context: context)
        try context.save()
        context.reset()
        return Seeded(context: context, owner: owner, studentID: ids[0], chainLessonIDs: chainLessonIDs)
    }

    private func enrollments(in context: NSManagedObjectContext) -> [CDStudentTrackEnrollmentEntity] {
        context.safeFetch(CDFetchRequest(CDStudentTrackEnrollmentEntity.self))
    }

    @Test("Enrolling writes one enrollment on the existing track and keeps its steps in lesson order")
    func enrollWritesOneEnrollment() throws {
        let seeded = try seed(perSequence: 10, students: 12)
        let context = seeded.context

        let trackID = SequenceTrackService.autoEnrollInTrackIfNeeded(
            lessonArea: "Math", lessonSequence: "Chains", studentIDs: [seeded.studentID],
            context: context, saveChanges: true
        )
        let track = try #require(
            try SequenceTrackService.cdGetTrack(area: "Math", sequence: "Chains", context: context)
        )
        #expect(trackID == track.id?.uuidString)
        let steps = ((track.steps?.allObjects as? [CDTrackStep]) ?? []).sorted { $0.orderIndex < $1.orderIndex }
        #expect(steps.map { $0.lessonTemplateID?.uuidString ?? "" } == seeded.chainLessonIDs)

        let rows = enrollments(in: context)
        #expect(rows.count == 1)
        #expect(rows.first?.studentID == seeded.studentID)
        #expect(rows.first?.trackID == trackID)
        #expect(rows.first?.isActive == true)
        #expect(rows.first?.student?.id?.uuidString == seeded.studentID)

        // A second enrolment is a no-op.
        _ = SequenceTrackService.autoEnrollInTrackIfNeeded(
            lessonArea: "Math", lessonSequence: "Chains", studentIDs: [seeded.studentID],
            context: context, saveChanges: true
        )
        #expect(enrollments(in: context).count == 1)
    }

    @Test("Completion check leaves an unfinished track active and closes a finished one")
    func completionCheckMatchesMastery() throws {
        let seeded = try seed(perSequence: 3, students: 4)
        let context = seeded.context
        _ = SequenceTrackService.autoEnrollInTrackIfNeeded(
            lessonArea: "Math", lessonSequence: "Chains", studentIDs: [seeded.studentID],
            context: context, saveChanges: true
        )

        SequenceTrackService.checkAndCompleteTrackIfNeeded(
            lessonArea: "Math", lessonSequence: "Chains", studentID: seeded.studentID, context: context
        )
        #expect(enrollments(in: context).first?.isActive == true)

        for lessonID in seeded.chainLessonIDs.dropFirst() {
            let mark = CDLessonPresentation(context: context)
            mark.studentID = seeded.studentID
            mark.lessonID = lessonID
            mark.state = .proficient
        }
        // Unsaved marks count, as they do when the caller owns the save.
        SequenceTrackService.checkAndCompleteTrackIfNeeded(
            lessonArea: "Math", lessonSequence: "Chains", studentID: seeded.studentID, context: context
        )
        #expect(enrollments(in: context).first?.isActive == false)
    }

    @Test("Enrolling and checking one student reads that sequence and student, not the classroom")
    func enrollAndCheckMaterialiseScopedRows() throws {
        let seeded = try seed(perSequence: 10, students: 12)
        let context = seeded.context
        let before = context.registeredObjects.count

        _ = SequenceTrackService.autoEnrollInTrackIfNeeded(
            lessonArea: "Math", lessonSequence: "Chains", studentIDs: [seeded.studentID],
            context: context, saveChanges: true
        )
        SequenceTrackService.checkAndCompleteTrackIfNeeded(
            lessonArea: "Math", lessonSequence: "Chains", studentID: seeded.studentID, context: context
        )
        let registered = context.registeredObjects.count - before
        // Sequence track, track, 10 chain lessons, 10 steps, the student, the
        // student's chain mark and the new enrollment: 24 measured. The
        // whole-table reads registered 90 (2026-09-18 baseline).
        #expect(registered <= 30, "registered \(registered) objects for one student")
    }

    /// The store the app really runs on. The split-store context has no
    /// CKShare, so the service will not create a track there; the rows are
    /// seeded directly and only the lookups are exercised.
    @Test("On SQLite, padded and differently cased names still resolve to their track")
    func sqliteLookupsFoldCaseAndWhitespace() throws {
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        let sequenceTrack = CDSequenceTrack(context: context)
        sequenceTrack.area = " math "
        sequenceTrack.sequence = "CHAINS"
        sequenceTrack.isExplicitlyDisabled = true
        let track = CDTrackEntity(context: context)
        track.title = " Math — Chains "
        let other = CDTrackEntity(context: context)
        other.title = "Math — Fractions"
        try context.save()
        context.reset()

        let foundSequence = try SequenceTrackService.cdGetSequenceTrack(
            area: "Math", sequence: "chains", context: context
        )
        #expect(foundSequence?.objectID == sequenceTrack.objectID)
        #expect(SequenceTrackService.isTrack(area: "Math", sequence: "chains", context: context) == false)
        #expect(try SequenceTrackService.cdGetSequenceTrack(area: "Math", sequence: "Beads", context: context) == nil)

        let foundTrack = try SequenceTrackService.cdGetTrack(area: "Math", sequence: "Chains", context: context)
        #expect(foundTrack?.objectID == track.objectID)
        #expect(try SequenceTrackService.cdGetTrack(area: "Math", sequence: "Beads", context: context) == nil)
    }
}
