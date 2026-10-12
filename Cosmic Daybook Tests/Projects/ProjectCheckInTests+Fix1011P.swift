import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-11, #65, #66 and #73.
// - #65: check-in work made in Uniform mode named its check-in but not the
//   type every project reader filters on, so the project and the check-in
//   showed none of it and deleting the project left it on the children.
// - #66: just opening an old check-in stamped its project active again.
// - #73: a check-in note open on one device wrote its stale text over a
//   newer edit made on another.

@Suite("Project check-ins (Fix1011P)")
@MainActor
struct ProjectCheckInTests {

    private struct Seeded {
        let project: CDProject
        let session: CDProjectSession
        let children: [CDStudent]
    }

    private func seed(_ context: NSManagedObjectContext) -> Seeded {
        let children = [
            CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Dahan"),
            CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        ]
        let project = CDProject(context: context)
        project.title = "Water Cycle"
        project.memberStudentIDsArray = children.compactMap { $0.id?.uuidString }
        let session = CDProjectSession(context: context)
        session.projectID = project.id?.uuidString ?? ""
        project.addToSessions(session)
        return Seeded(project: project, session: session, children: children)
    }

    private func makeUniformWork(_ seeded: Seeded, in context: NSManagedObjectContext) throws -> [CDWorkModel] {
        let service = SessionWorkAssignmentService(context: context)
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Project Work", area: "Projects")
        let lessonID = try #require(lesson.id)
        return try seeded.children.compactMap { child in
            try service.createUniformWork(
                session: seeded.session,
                studentID: child.id?.uuidString ?? "",
                lessonID: lessonID,
                title: "Water Cycle: Follow-Up",
                instructions: "Draw the cycle.",
                scheduledDate: AppCalendar.startOfDay(Date())
            )
        }
    }

    // MARK: - #65

    @Test("Uniform check-in work is typed as project work, so the check-in finds it")
    func uniformWorkIsTyped() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let seeded = seed(context)
        let works = try makeUniformWork(seeded, in: context)
        #expect(works.count == 2)
        #expect(CoreDataTestHelpers.save(context))

        let sessionID = try #require(seeded.session.id).uuidString
        for work in works {
            #expect(work.sourceContextType == .projectSession)
            #expect(work.sourceContextID == sessionID)
        }
    }

    @Test("Deleting the project takes its Uniform check-in work with it")
    func deletingProjectRemovesUniformWork() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let seeded = seed(context)
        _ = try makeUniformWork(seeded, in: context)
        #expect(CoreDataTestHelpers.save(context))

        ProjectDeletion.delete(seeded.project, in: context)
        #expect(CoreDataTestHelpers.save(context))

        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "title == %@", "Water Cycle: Follow-Up")
        #expect(context.safeFetch(request).isEmpty, "no follow-up outlives its project")
    }

    // MARK: - #66

    @Test("Leaving a check-in with nothing changed doesn't mark its project active")
    func noChangeNoStamp() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let seeded = seed(context)
        let works = try makeUniformWork(seeded, in: context)
        let lastYear = Date(timeIntervalSinceNow: -400 * 24 * 3600)
        seeded.project.modifiedAt = lastYear
        #expect(CoreDataTestHelpers.save(context))

        let shouldSave = ProjectCheckInSave.prepareSave(seeded.session, works: works)
        #expect(!shouldSave)
        #expect(seeded.project.modifiedAt == lastYear)
        #expect(!context.hasChanges)
    }

    @Test("A real edit on the check-in or one of its follow-ups does mark the project active")
    func realChangeStamps() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let seeded = seed(context)
        let works = try makeUniformWork(seeded, in: context)
        let lastYear = Date(timeIntervalSinceNow: -400 * 24 * 3600)
        seeded.project.modifiedAt = lastYear
        #expect(CoreDataTestHelpers.save(context))

        seeded.session.chapterOrPages = "Evaporation"
        #expect(ProjectCheckInSave.prepareSave(seeded.session, works: works))
        #expect(seeded.project.modifiedAt != lastYear)
        #expect(CoreDataTestHelpers.save(context))

        seeded.project.modifiedAt = lastYear
        #expect(CoreDataTestHelpers.save(context))
        let work = try #require(works.first)
        work.setLegacyNoteText("Finished the diagram.", in: context)
        #expect(ProjectCheckInSave.prepareSave(seeded.session, works: works))
        #expect(seeded.project.modifiedAt != lastYear)
    }

    // MARK: - #73

    @Test("A note field she didn't touch never writes over a newer note from another device")
    func untouchedFieldLeavesNewerNote() {
        let write = ProjectCheckInSave.noteToWrite(
            typed: "Started the poster.",
            base: "Started the poster.",
            stored: "Started the poster. Added the arrows on the iPad."
        )
        #expect(write == nil)
    }

    @Test("Her own edit is written; when the note also changed elsewhere, both are kept")
    func editsAreWrittenAndMerged() throws {
        let edited = ProjectCheckInSave.noteToWrite(typed: "Poster done. ", base: "Poster", stored: "Poster")
        #expect(edited == "Poster done.")
        #expect(ProjectCheckInSave.noteToWrite(typed: "Poster", base: "Poster", stored: "Poster") == nil)

        let merged = try #require(ProjectCheckInSave.noteToWrite(
            typed: "Poster. Needs a title.",
            base: "Poster.",
            stored: "Poster. Arrows added."
        ))
        #expect(merged.contains("Arrows added."))
        #expect(merged.contains("Needs a title."))
    }
}
