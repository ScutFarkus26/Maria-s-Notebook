import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// The 2026-09-30 store audit found ~3,340 records the notebook no longer reads.
// Each test seeds one kind of junk beside a look-alike that must stay, then
// checks the preview counts it and the run removes only it.

@Suite("Notebook junk cleanup")
@MainActor
struct NotebookJunkCleanupTests {

    private let today: Date

    init() throws {
        today = try CoreDataTestHelpers.day("2026-10-01")
    }

    private func count<T: NSManagedObject>(_ type: T.Type, in context: NSManagedObjectContext) -> Int {
        context.safeFetch(CDFetchRequest(type)).filter { !$0.isDeleted }.count
    }

    /// Previews, runs and saves; returns the run's counts after checking the preview agreed.
    private func clean(_ context: NSManagedObjectContext) -> NotebookJunkCleanup.Counts {
        let preview = NotebookJunkCleanup.run(in: context, today: today, apply: false)
        #expect(!context.hasChanges, "the preview changed something")
        let done = NotebookJunkCleanup.run(in: context, today: today, apply: true)
        #expect(done == preview)
        #expect(CoreDataTestHelpers.save(context))
        return done
    }

    @Test("A clean notebook has nothing to clean up")
    func cleanNotebook() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let student = CoreDataTestHelpers.seedStudent(in: context)
        let lesson = CoreDataTestHelpers.seedLesson(in: context)
        let work = CoreDataTestHelpers.seedWorkModel(
            in: context, studentID: try #require(student.id), lessonID: try #require(lesson.id)
        )
        let participant = CDWorkParticipantEntity(context: context)
        participant.studentID = student.id?.uuidString ?? ""
        participant.work = work
        CoreDataTestHelpers.seedNote(in: context, body: "Worked on the bead frame")
        CoreDataTestHelpers.save(context)

        #expect(clean(context).isEmpty)
        #expect(count(CDWorkParticipantEntity.self, in: context) == 1)
        #expect(count(CDNote.self, in: context) == 1)
    }

    @Test("Track steps with no track and tracks nothing uses go; a used empty track stays")
    func tracksAndSteps() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context)
        let kept = CDTrackEntity(context: context)
        kept.title = "Math — Laws"
        let keptStep = CDTrackStep(context: context)
        keptStep.lessonTemplateID = lesson.id
        keptStep.track = kept
        let orphan = CDTrackStep(context: context)
        orphan.lessonTemplateID = lesson.id
        let unused = CDTrackEntity(context: context)
        unused.title = "Biology — Zoology"
        let namedByWork = CDTrackEntity(context: context)
        namedByWork.title = "Book Clubs — Book Club"
        CoreDataTestHelpers.save(context)
        let work = CoreDataTestHelpers.seedWorkModel(in: context)
        work.trackID = namedByWork.id?.uuidString
        CoreDataTestHelpers.save(context)

        let done = clean(context)
        #expect(done.orphanTrackSteps == 1)
        #expect(done.emptyTracks == 1)
        #expect(Set(context.safeFetch(CDFetchRequest(CDTrackEntity.self)).map(\.title))
            == ["Math — Laws", "Book Clubs — Book Club"])
        #expect(count(CDTrackStep.self, in: context) == 1)
    }

    @Test("Presentation records with no child and no lesson, or of a deleted lesson, go")
    func presentations() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let student = CoreDataTestHelpers.seedStudent(in: context)
        let lesson = CoreDataTestHelpers.seedLesson(in: context)
        CoreDataTestHelpers.save(context)
        for (studentID, lessonID) in [
            ("", ""),
            (student.id?.uuidString ?? "", UUID().uuidString),
            (student.id?.uuidString ?? "", lesson.id?.uuidString.lowercased() ?? "")
        ] {
            let record = CDLessonPresentation(context: context)
            record.studentID = studentID
            record.lessonID = lessonID
        }
        CoreDataTestHelpers.save(context)

        let done = clean(context)
        #expect(done.blankPresentations == 1)
        #expect(done.presentationsOfDeletedLessons == 1)
        let left = context.safeFetch(CDFetchRequest(CDLessonPresentation.self))
        #expect(left.map(\.lessonID) == [lesson.id?.uuidString.lowercased() ?? ""])
    }

    @Test("Work children with no work go, and completion records of deleted work")
    func workLeftovers() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let work = CoreDataTestHelpers.seedWorkModel(in: context)
        let detached = CDWorkParticipantEntity(context: context)
        detached.studentID = UUID().uuidString
        let step = CDWorkStep(context: context)
        step.title = "Step 1"
        let sampleStep = CDSampleWorkStep(context: context)
        sampleStep.title = "Sample step"
        let gone = CDWorkCompletionRecord(context: context)
        gone.workID = UUID().uuidString
        let live = CDWorkCompletionRecord(context: context)
        live.workID = work.id?.uuidString ?? ""
        CoreDataTestHelpers.save(context)

        let done = clean(context)
        #expect(done.detachedWorkParticipants == 1)
        #expect(done.orphanWorkSteps == 1)
        #expect(done.orphanSampleWorkSteps == 1)
        #expect(done.completionRecordsOfDeletedWork == 1)
        #expect(context.safeFetch(CDFetchRequest(CDWorkCompletionRecord.self)).map(\.workID)
            == [work.id?.uuidString ?? ""])
    }

    @Test("Only past, unlocked, blank attendance rows go")
    func blankAttendance() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let past = try CoreDataTestHelpers.day("2026-09-28")
        let locked = try CoreDataTestHelpers.day("2026-09-29")
        let child = UUID()
        let blank = CoreDataTestHelpers.seedAttendance(in: context, studentID: child, date: past)
        let present = CoreDataTestHelpers.seedAttendance(in: context, studentID: UUID(), date: past)
        present.status = .present
        let noted = CoreDataTestHelpers.seedAttendance(in: context, studentID: UUID(), date: past)
        noted.note = "Picked up early"
        CoreDataTestHelpers.seedAttendance(in: context, studentID: child, date: locked)
        CoreDataTestHelpers.seedAttendance(in: context, studentID: child, date: today)
        CoreDataTestHelpers.seedAttendance(
            in: context, studentID: child, date: try CoreDataTestHelpers.day("2026-10-13")
        )
        let lock = CDAttendanceDayLock(context: context)
        lock.date = AppCalendar.startOfDay(locked)
        CoreDataTestHelpers.save(context)
        let blankID = blank.objectID

        let done = clean(context)
        #expect(done.blankAttendance == 1)
        #expect(count(CDAttendanceRecord.self, in: context) == 5)
        #expect(context.registeredObject(for: blankID)?.isDeleted ?? true)
    }

    @Test("Unlinked reminder copies go; a reminder that only exists unlinked keeps its oldest copy")
    func duplicateReminders() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let due = try CoreDataTestHelpers.day("2026-09-11")
        func reminder(_ title: String, linked: String?, created: String) throws {
            let row = CDReminder(context: context)
            row.title = title
            row.dueDate = due
            row.eventKitReminderID = linked
            row.createdAt = try CoreDataTestHelpers.day(created)
        }
        try reminder("Order paper", linked: "EK-1", created: "2025-04-26")
        try reminder("Order paper", linked: nil, created: "2025-04-26")
        try reminder("order paper ", linked: nil, created: "2025-09-07")
        try reminder("Call the office", linked: nil, created: "2025-05-01")
        try reminder("Call the office", linked: nil, created: "2025-06-25")
        try reminder("Field trip forms", linked: nil, created: "2025-06-25")
        CoreDataTestHelpers.save(context)

        let done = clean(context)
        #expect(done.duplicateReminders == 3)
        let left = context.safeFetch(CDFetchRequest(CDReminder.self))
        #expect(left.count == 3)
        #expect(left.contains { $0.eventKitReminderID == "EK-1" })
        let office = left.filter { $0.title == "Call the office" }
        #expect(office.map(\.createdAt) == [try CoreDataTestHelpers.day("2025-05-01")])
    }

    @Test("Notes with nothing in them go; a flagged or tagged empty note stays")
    func emptyNotes() throws {
        let context = try CoreDataTestHelpers.makeContext()
        CoreDataTestHelpers.seedNote(in: context, body: "  \n")
        CoreDataTestHelpers.seedNote(in: context, body: "Read for 20 minutes")
        CoreDataTestHelpers.seedNote(in: context, body: "").needsFollowUp = true
        CoreDataTestHelpers.seedNote(in: context, body: "").tagsArray = ["Math"]
        CoreDataTestHelpers.seedNote(in: context, body: "").imagePath = "photo.jpg"
        for note in context.registeredObjects.compactMap({ $0 as? CDNote }) {
            note.includeInReport = false
        }
        CoreDataTestHelpers.save(context)

        let done = clean(context)
        #expect(done.emptyNotes == 1)
        #expect(count(CDNote.self, in: context) == 4)
    }

    @Test("Documents with no file at all go")
    func documentsWithoutFile() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let empty = CDDocument(context: context)
        empty.title = "Progress Report"
        let filed = CDDocument(context: context)
        filed.title = "Report card"
        filed.pdfFileRelativePath = "Student Files/report.pdf"
        CoreDataTestHelpers.save(context)

        let done = clean(context)
        #expect(done.documentsWithoutFile == 1)
        #expect(context.safeFetch(CDFetchRequest(CDDocument.self)).map(\.title) == ["Report card"])
    }

    @Test("Old enrollments take their track, or go when the child is already on it or nothing matches")
    func oldEnrollments() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let avital = CoreDataTestHelpers.seedStudent(in: context, firstName: "Avital")
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora")
        let fractions = CDTrackEntity(context: context)
        fractions.title = "Math — Fractions"
        CoreDataTestHelpers.save(context)
        func enroll(_ student: CDStudent, key: String, track: CDTrackEntity? = nil) {
            let enrollment = CDStudentTrackEnrollmentEntity(context: context)
            enrollment.studentID = student.id?.uuidString ?? ""
            enrollment.trackID = key
            enrollment.track = track
            enrollment.isActive = true
        }
        let fractionsID = fractions.id?.uuidString ?? ""
        enroll(avital, key: fractionsID, track: fractions)  // Avital is already on it
        enroll(avital, key: "Math|Fractions")                // a duplicate of hers
        enroll(ora, key: "Math|Fractions")                   // Ora's only link to it
        enroll(ora, key: "New|")                             // matches no track
        enroll(ora, key: UUID().uuidString)                  // a track that's gone
        CoreDataTestHelpers.save(context)

        let done = clean(context)
        #expect(done.enrollmentsRelinked == 1)
        #expect(done.enrollmentsRemoved == 3)
        #expect(done.emptyTracks == 0)
        let left = context.safeFetch(CDFetchRequest(CDStudentTrackEnrollmentEntity.self))
        #expect(left.count == 2)
        let tracks: Set<NSManagedObjectID?> = Set(left.map { $0.track?.objectID })
        let trackIDs: Set<String> = Set(left.map(\.trackID))
        let students: Set<String> = Set(left.map(\.studentID))
        let expectedStudents: Set<String> = [try #require(avital.id).uuidString, try #require(ora.id).uuidString]
        #expect(tracks == [fractions.objectID])
        #expect(trackIDs == [fractionsID])
        #expect(students == expectedStudents)
    }

    @Test("Planned lessons of children who've left are skipped, never deleted")
    func departedPlans() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let left = CoreDataTestHelpers.seedStudent(in: context, firstName: "Naomi", enrollmentStatus: .withdrawn)
        let moved = CoreDataTestHelpers.seedStudent(in: context, firstName: "Hadar", enrollmentStatus: .transferred)
        let here = CoreDataTestHelpers.seedStudent(in: context, firstName: "Leshem")
        CoreDataTestHelpers.save(context)
        for student in [left, moved, here] {
            let entry = CDYearPlanEntry(context: context)
            entry.studentID = student.id?.uuidString ?? ""
            entry.lessonID = UUID().uuidString
            entry.status = .planned
        }
        CoreDataTestHelpers.save(context)

        let done = clean(context)
        #expect(done.departedPlansSkipped == 2)
        #expect(done.removed == 0)
        let entries = context.safeFetch(CDFetchRequest(CDYearPlanEntry.self))
        #expect(entries.count == 3)
        #expect(entries.filter { $0.status == .skipped }.count == 2)
        #expect(entries.first { $0.studentID == here.id?.uuidString }?.status == .planned)
    }

    @Test("A second run finds nothing")
    func idempotent() throws {
        let context = try CoreDataTestHelpers.makeContext()
        CDTrackStep(context: context).lessonTemplateID = UUID()
        CDWorkParticipantEntity(context: context).studentID = UUID().uuidString
        CoreDataTestHelpers.seedNote(in: context, body: "").includeInReport = false
        CoreDataTestHelpers.save(context)

        #expect(clean(context).removed == 3)
        #expect(NotebookJunkCleanup.run(in: context, today: today, apply: false).isEmpty)
    }
}
