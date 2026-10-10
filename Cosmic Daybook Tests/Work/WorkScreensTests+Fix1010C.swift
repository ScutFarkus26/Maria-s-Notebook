import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-10, Part 2 #49–#58: the work screens' own saves, steps,
/// practice sessions, the cohort list and the Works log's paging.
@Suite("Work Screens (fix 10-10 C)")
@MainActor
struct WorkScreensFix1010CTests {

    private func makeContext() throws -> NSManagedObjectContext {
        try CoreDataTestHelpers.makeInMemoryStack().viewContext
    }

    private func steps(of work: CDWorkModel) -> [String] {
        work.orderedSteps.map(\.title)
    }

    // MARK: - Saving one sheet's edit (#49, #54)

    @Test("a sheet's edit is saved on its own Save")
    func scopedEditSaves() throws {
        let context = try makeContext()
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Report on whales")
        CoreDataTestHelpers.save(context)

        let saved = SaveCoordinator().saveEdit(in: context, reason: "Save work step") {
            _ = try WorkStepService(context: context).createStep(for: work, title: "Set 1")
        }
        #expect(saved)
        #expect(!context.hasChanges)
        #expect(steps(of: work) == ["Set 1"])
    }

    @Test("a failed save takes back only that sheet's edit, so Save again doesn't make it twice")
    func failedScopedEditTakesBackOnlyItsOwnChange() throws {
        let context = try makeContext()
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Report on whales")
        CoreDataTestHelpers.save(context)
        // Some other screen's unsaved row that can't be saved.
        let other = CDWorkModel(context: context)
        other.setValue(nil, forKey: "title")

        let saved = SaveCoordinator().saveEdit(in: context, reason: "Save work step") {
            _ = try WorkStepService(context: context).createStep(for: work, title: "Set 1")
        }
        #expect(!saved)
        #expect(work.orderedSteps.isEmpty)
        #expect(!context.insertedObjects.contains { $0 is CDWorkStep })
        #expect(context.insertedObjects.contains(other))
    }

    // MARK: - Step numbers (#58)

    @Test("deleting a step closes the gap in the numbering")
    func deletingAStepRenumbers() throws {
        let context = try makeContext()
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Report on whales")
        let service = WorkStepService(context: context)
        for title in ["One", "Two", "Three", "Four"] {
            try service.createStep(for: work, title: title)
        }
        CoreDataTestHelpers.save(context)

        try service.delete(work.orderedSteps[1], from: work)
        #expect(steps(of: work) == ["One", "Three", "Four"])
        #expect(work.orderedSteps.map(\.orderIndex) == [0, 1, 2])
    }

    // MARK: - Record Practice's check-in (#52)

    @Test("Record Practice's check-in is a real check-in on each child's open work, once per day")
    func recordPracticeSchedulesRealCheckIns() throws {
        let context = try makeContext()
        let lessonID = UUID()
        let maya = CoreDataTestHelpers.seedWorkModel(in: context, title: "Checkerboard", lessonID: lessonID)
        let eli = CoreDataTestHelpers.seedWorkModel(in: context, title: "Checkerboard", lessonID: lessonID)
        let closed = CoreDataTestHelpers.seedWorkModel(in: context, title: "Checkerboard", lessonID: lessonID)
        closed.status = .mastered
        let day = try CoreDataTestHelpers.day("2026-09-24")
        CDWorkCheckIn.make(for: eli, on: day, purpose: "Progress Check", in: context)
        CoreDataTestHelpers.save(context)

        let made = PracticeCheckInScheduler.schedule(
            on: day.addingTimeInterval(9 * 3600), for: [maya, eli, closed], in: context
        )
        #expect(made.map(\.work) == [maya])
        #expect(made.first?.date == AppCalendar.startOfDay(day))
        #expect(made.first?.status == .scheduled)
        #expect(WorkLogService.checkIns(of: eli, in: context).count == 1)
        #expect(WorkLogService.checkIns(of: closed, in: context).isEmpty)
    }

    @Test("Practice Overview counts only check-ins from today on")
    func upcomingCheckInsAreUpcoming() throws {
        let context = try makeContext()
        let today = try CoreDataTestHelpers.day("2026-10-08")
        let dates: [Date?] = [
            AppCalendar.addingDays(-7, to: today), today, AppCalendar.addingDays(3, to: today), nil
        ]
        let sessions = dates.map { date -> CDPracticeSession in
            let session = CDPracticeSession(context: context)
            session.checkInScheduledFor = date
            return session
        }
        let stats = PracticeStatsCalculator.calculate(from: sessions, today: today.addingTimeInterval(15 * 3600))
        #expect(stats.upcomingCheckIns == 2)
    }

    // MARK: - Practice partners (#58)

    @Test("Learned Together is the presentation this work follows, not the first record of the lesson")
    func coLearnersComeFromThisWorksPresentation() throws {
        let context = try makeContext()
        let lessonID = UUID()
        let maya = UUID()
        let ana = UUID()
        let eli = UUID()
        let old = PresentationFactory.makePresented(
            lessonID: lessonID, studentIDs: [maya, ana],
            presentedAt: try CoreDataTestHelpers.day("2025-02-03"), context: context
        )
        let recent = PresentationFactory.makePresented(
            lessonID: lessonID, studentIDs: [maya, eli],
            presentedAt: try CoreDataTestHelpers.day("2026-09-14"), context: context
        )
        let work = CoreDataTestHelpers.seedWorkModel(in: context, studentID: maya, lessonID: lessonID)

        work.presentationID = recent.id?.uuidString
        #expect(StudentCategorizer.getCoLearnerIDs(for: work, allLessonAssignments: [old, recent]) == [maya, eli])

        // No presentation on the work: her latest given one.
        work.presentationID = nil
        #expect(StudentCategorizer.getCoLearnerIDs(for: work, allLessonAssignments: [old, recent]) == [maya, eli])
    }

    @Test("an Incomplete row isn't Recently Completed; a Mastered one is")
    func incompleteIsNotRecentlyCompleted() throws {
        let context = try makeContext()
        let lessonID = UUID()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya")
        let eli = CoreDataTestHelpers.seedStudent(in: context, firstName: "Eli")
        let mayaID = try #require(maya.id)
        let eliID = try #require(eli.id)
        let initial = CoreDataTestHelpers.seedWorkModel(in: context, studentID: mayaID, lessonID: lessonID)
        let elis = CoreDataTestHelpers.seedWorkModel(in: context, studentID: eliID, lessonID: lessonID)
        elis.status = .incomplete
        elis.completedAt = AppCalendar.addingDays(-3, to: Date())

        let categorizer = StudentCategorizer(
            initialWorkItem: initial, allWork: [initial, elis],
            allLessonAssignments: [], allPracticeSessions: [], coLearnerIDs: []
        )
        #expect(categorizer.categorize(eli).category != .recentlyPassed)

        elis.status = .mastered
        #expect(categorizer.categorize(eli).category == .recentlyPassed)
    }

    // MARK: - Lesson Cohort (#55)

    @Test("the cohort shows each classmate's open row first, and leaves out a child who has left")
    func cohortPrefersOpenRowsAndEnrolledChildren() throws {
        let context = try makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Checkerboard")
        let lessonID = try #require(lesson.id)
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya")
        let eli = CoreDataTestHelpers.seedStudent(in: context, firstName: "Eli")
        let ana = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ana", enrollmentStatus: .withdrawn)
        let eliID = try #require(eli.id)
        let mine = CoreDataTestHelpers.seedWorkModel(in: context, studentID: try #require(maya.id), lessonID: lessonID)
        // Eli's finished row is fetched before his open one.
        let elisOld = CoreDataTestHelpers.seedWorkModel(in: context, studentID: eliID, lessonID: lessonID)
        elisOld.status = .mastered
        let elisOpen = CoreDataTestHelpers.seedWorkModel(in: context, studentID: eliID, lessonID: lessonID)
        CoreDataTestHelpers.seedWorkModel(in: context, studentID: try #require(ana.id), lessonID: lessonID)
        CoreDataTestHelpers.save(context)

        let viewModel = WorkDetailViewModel(workID: try #require(mine.id))
        viewModel.loadWork(modelContext: context, saveCoordinator: SaveCoordinator())

        #expect(viewModel.lessonCohort.map(\.student.firstName) == ["Eli"])
        #expect(viewModel.lessonCohort.first?.status == .active)
        #expect(viewModel.peerWorkIDs[eliID] == elisOpen.id)
    }

    // MARK: - Note actions (#50)

    @Test("reloading the notes keeps the header's unsaved edits")
    func reloadingNotesKeepsHeaderEdits() throws {
        let context = try makeContext()
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Checkerboard")
        CoreDataTestHelpers.save(context)
        let viewModel = WorkDetailViewModel(workID: try #require(work.id))
        viewModel.loadWork(modelContext: context, saveCoordinator: SaveCoordinator())
        viewModel.workTitle = "Checkerboard, two digits"
        viewModel.status = .keepPracticing
        viewModel.completionNote = "Needs the bead frame again"

        let note = CoreDataTestHelpers.seedNote(in: context, body: "Worked with Eli")
        note.work = work
        CoreDataTestHelpers.save(context)
        viewModel.reloadNotes()

        #expect(viewModel.workModelNotes.map(\.body) == ["Worked with Eli"])
        #expect(viewModel.workTitle == "Checkerboard, two digits")
        #expect(viewModel.status == .keepPracticing)
        #expect(viewModel.completionNote == "Needs the bead frame again")
    }

    // MARK: - The Works log's paging (#56)

    @Test("clearing a filter that left 12 of 200 shows a full first page again")
    func pagingRecoversAfterAFilterClears() {
        let pagination = PaginationState(pageSize: 50)
        pagination.updateTotal(200)
        #expect(pagination.displayedCount == 50)

        pagination.updateTotal(12)
        #expect(pagination.displayedCount == 12)
        #expect(!pagination.hasMore)

        pagination.updateTotal(200)
        #expect(pagination.displayedCount == 50)
        #expect(pagination.hasMore)
    }
}
