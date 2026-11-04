import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// A classroom of two lessons in one sequence and two children, Maya and
/// Eli, for the work page's tests.
@MainActor
struct Fix1103W1WorkPage {
    let context: NSManagedObjectContext
    let saveCoordinator = SaveCoordinator()
    let first: CDLesson
    let second: CDLesson
    let maya: UUID
    let eli: UUID

    var firstID: UUID { first.id ?? UUID() }
    var secondID: UUID { second.id ?? UUID() }

    static func make() throws -> Fix1103W1WorkPage {
        let context = try CoreDataTestHelpers.makeContext()
        let first = CoreDataTestHelpers.seedLesson(
            in: context, name: "Golden Bead Addition", area: "Math", sequence: "Golden Beads"
        )
        first.orderInSequence = 1
        let second = CoreDataTestHelpers.seedLesson(
            in: context, name: "Golden Bead Subtraction", area: "Math", sequence: "Golden Beads"
        )
        second.orderInSequence = 2
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        let eli = CoreDataTestHelpers.seedStudent(in: context, firstName: "Eli", lastName: "Park")
        #expect(CoreDataTestHelpers.save(context))
        return Fix1103W1WorkPage(
            context: context, first: first, second: second,
            maya: try #require(maya.id), eli: try #require(eli.id)
        )
    }

    /// A child's own work on the first lesson.
    func work(for studentID: UUID, kind: WorkKind = .practiceLesson, title: String = "Addition") -> CDWorkModel {
        let work = CoreDataTestHelpers.seedWorkModel(
            in: context, title: title, studentID: studentID, lessonID: firstID
        )
        work.kind = kind
        #expect(CoreDataTestHelpers.save(context))
        return work
    }

    /// The page opened on `work`.
    func page(
        for work: CDWorkModel, testStudents: (show: Bool, names: String)? = nil
    ) throws -> WorkDetailViewModel {
        let page = WorkDetailViewModel(workID: try #require(work.id))
        page.testStudentSettings = testStudents
        page.loadWork(modelContext: context, saveCoordinator: saveCoordinator)
        return page
    }

    func plans(of lessonID: UUID) -> [CDLessonAssignment] {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lessonID.uuidString)
        return context.safeFetch(request)
    }

    /// One Quick New Work for these children: a row per child, each naming
    /// every other child, as the sheet makes them.
    func quickNewWork(for students: [UUID]) -> [CDWorkModel] {
        let made = Date()
        let works = students.map { studentID in
            let work = CoreDataTestHelpers.seedWorkModel(
                in: context, title: "Addition", studentID: studentID, lessonID: firstID
            )
            work.kind = .practiceLesson
            work.createdAt = made
            return work
        }
        for work in works {
            for other in works where other !== work {
                let participant = CDWorkParticipantEntity(context: context)
                participant.id = UUID()
                participant.studentID = other.studentID
                participant.work = work
            }
        }
        #expect(CoreDataTestHelpers.save(context))
        return works
    }

    /// One row carrying several children, as project work is made.
    func sharedRow(owner: UUID, children: [UUID]) -> CDWorkModel {
        let work = self.work(for: owner)
        for child in children {
            let participant = CDWorkParticipantEntity(context: context)
            participant.id = UUID()
            participant.studentID = child.uuidString
            participant.work = work
        }
        #expect(CoreDataTestHelpers.save(context))
        return work
    }

    var liveNotes: [String] {
        context.safeFetch(CDFetchRequest(CDNote.self)).filter { !$0.isDeleted }.map(\.body)
    }
}

/// Bug hunt 2026-11-03, the work page (#19, #33, #34, #36): Unlock Next
/// Lesson on a group plan and twice, Save over a status or title changed
/// elsewhere, and Working With, Project Group and the cohort. Each runs the
/// way the page runs it, through `WorkDetailViewModel`.
@Suite("Work page (fix 11-03 W1)")
@MainActor
struct WorkPageFix1103W1Tests {

    // MARK: - Unlock Next Lesson (#19, #34)

    @Test("Unlock for one child leaves her group's plan alone and gives her an unlocked plan of her own")
    func unlockLeavesGroupPlanAlone() throws {
        let fixture = try Fix1103W1WorkPage.make()
        let mine = fixture.work(for: fixture.maya)
        let group = PresentationFactory.makeDraft(
            lessonID: fixture.secondID, studentIDs: [fixture.maya, fixture.eli], context: fixture.context
        )
        #expect(CoreDataTestHelpers.save(fixture.context))
        let page = try fixture.page(for: mine)

        page.status = .mastered
        page.offerUnlock()
        #expect(page.showUnlockNextLessonAlert)
        page.unlockNextLesson(modelContext: fixture.context, saveCoordinator: fixture.saveCoordinator)

        #expect(!group.manuallyUnblocked, "Eli hasn't finished the lesson before")
        #expect(Set(group.resolvedStudentIDs) == [fixture.maya, fixture.eli])
        let hers = fixture.plans(of: fixture.secondID).filter { $0 !== group }
        #expect(hers.count == 1)
        #expect(hers.first?.resolvedStudentIDs == [fixture.maya])
        #expect(hers.first?.manuallyUnblocked == true)
        #expect(!fixture.context.hasChanges)
    }

    @Test("Unlock reuses her own plan of the next lesson rather than making another")
    func unlockReusesHerOwnPlan() throws {
        let fixture = try Fix1103W1WorkPage.make()
        let mine = fixture.work(for: fixture.maya)
        let solo = PresentationFactory.makeDraft(
            lessonID: fixture.secondID, studentIDs: [fixture.maya], context: fixture.context
        )
        #expect(CoreDataTestHelpers.save(fixture.context))
        let page = try fixture.page(for: mine)

        page.unlockNextLesson(modelContext: fixture.context, saveCoordinator: fixture.saveCoordinator)

        #expect(solo.manuallyUnblocked)
        #expect(fixture.plans(of: fixture.secondID).count == 1)
    }

    @Test("Unlocking twice makes one plan, and the page doesn't offer it a second time")
    func unlockTwiceMakesOneDraft() throws {
        let fixture = try Fix1103W1WorkPage.make()
        let mine = fixture.work(for: fixture.maya)
        let page = try fixture.page(for: mine)

        page.status = .mastered
        page.offerUnlock()
        #expect(page.showUnlockNextLessonAlert)
        page.unlockNextLesson(modelContext: fixture.context, saveCoordinator: fixture.saveCoordinator)

        // Mastered picked again, or the Unlock pill tapped.
        page.showUnlockNextLessonAlert = false
        page.offerUnlock()
        #expect(!page.showUnlockNextLessonAlert, "it is unlocked already")
        // The same alert still up in a second window.
        page.unlockNextLesson(modelContext: fixture.context, saveCoordinator: fixture.saveCoordinator)

        let made = fixture.plans(of: fixture.secondID)
        #expect(made.count == 1)
        #expect(made.first?.manuallyUnblocked == true)
    }

    // MARK: - Save over changes made elsewhere (#33)

    @Test("Save with a note keeps a Mastered set elsewhere while the page was open")
    func saveKeepsStatusSetElsewhere() throws {
        let fixture = try Fix1103W1WorkPage.make()
        let mine = fixture.work(for: fixture.maya)
        let page = try fixture.page(for: mine)

        // Marked Mastered from the grid (or by Claude) while the page is open.
        try WorkLogService.log(
            [.init(work: mine, status: .mastered, note: nil)],
            context: fixture.context, saveCoordinator: fixture.saveCoordinator
        )
        page.completionNote = "Did the second row on her own"
        #expect(page.save(modelContext: fixture.context, saveCoordinator: fixture.saveCoordinator))

        #expect(mine.status == .mastered)
        #expect(fixture.liveNotes.contains("Did the second row on her own"))
        #expect(!fixture.context.hasChanges)
    }

    @Test("Save leaves a title renamed elsewhere while the page was open")
    func saveKeepsTitleSetElsewhere() throws {
        let fixture = try Fix1103W1WorkPage.make()
        let mine = fixture.work(for: fixture.maya, title: "Bead chain 7")
        let page = try fixture.page(for: mine)

        mine.title = "Bead chain 7 and 8"
        #expect(CoreDataTestHelpers.save(fixture.context))
        #expect(page.save(modelContext: fixture.context, saveCoordinator: fixture.saveCoordinator))

        #expect(mine.title == "Bead chain 7 and 8")
    }

    @Test("A status and title she changed on the page are still saved")
    func touchedFieldsStillSave() throws {
        let fixture = try Fix1103W1WorkPage.make()
        let mine = fixture.work(for: fixture.maya, title: "Bead chain 7")
        let page = try fixture.page(for: mine)

        page.status = .keepPracticing
        page.workTitle = "Bead chain 7, again"
        #expect(page.save(modelContext: fixture.context, saveCoordinator: fixture.saveCoordinator))

        #expect(mine.status == .keepPracticing)
        #expect(mine.title == "Bead chain 7, again")
    }

    @Test("A status set elsewhere shows on the open page; one she picked herself stays and is saved")
    func headerFollowsTheRowUnlessTouched() throws {
        let fixture = try Fix1103W1WorkPage.make()
        let mine = fixture.work(for: fixture.maya)
        let elis = fixture.work(for: fixture.eli)
        let untouched = try fixture.page(for: mine)
        let touched = try fixture.page(for: elis)
        touched.status = .keepPracticing

        for work in [mine, elis] {
            try WorkLogService.log(
                [.init(work: work, status: .mastered, note: nil)],
                context: fixture.context, saveCoordinator: fixture.saveCoordinator
            )
        }
        untouched.refreshHeaderFromStore()
        touched.refreshHeaderFromStore()

        #expect(untouched.status == .mastered)
        #expect(touched.status == .keepPracticing)
        #expect(touched.save(modelContext: fixture.context, saveCoordinator: fixture.saveCoordinator))
        #expect(elis.status == .keepPracticing)
    }

    // MARK: - Working With, Project Group and the cohort (#36)

    @Test("Quick New Work copies show no Working With; the classmate is in the cohort from her own copy")
    func linkedCopiesShowNoWorkingWith() throws {
        let fixture = try Fix1103W1WorkPage.make()
        let copies = fixture.quickNewWork(for: [fixture.maya, fixture.eli])
        let page = try fixture.page(for: copies[0])

        #expect(page.workParticipants.isEmpty)
        #expect(page.lessonCohort.compactMap(\.student.id) == [fixture.eli])
    }

    @Test("A shared row's Working With leaves out a child who has left")
    func sharedRowLeavesOutDepartedChild() throws {
        let fixture = try Fix1103W1WorkPage.make()
        let ana = CoreDataTestHelpers.seedStudent(
            in: fixture.context, firstName: "Ana", lastName: "Ruiz", enrollmentStatus: .withdrawn
        )
        let row = fixture.sharedRow(
            owner: fixture.maya, children: [fixture.maya, fixture.eli, try #require(ana.id)]
        )
        let page = try fixture.page(for: row)

        #expect(page.workParticipants.compactMap(\.student.id) == [fixture.eli])
    }

    @Test("Group Meeting asks the classmates on linked copies, but not one who has left")
    func groupMeetingAsksLinkedCopiesStillInTheRoom() throws {
        let fixture = try Fix1103W1WorkPage.make()
        let ana = CoreDataTestHelpers.seedStudent(
            in: fixture.context, firstName: "Ana", lastName: "Ruiz", enrollmentStatus: .withdrawn
        )
        let copies = fixture.quickNewWork(for: [fixture.maya, fixture.eli, try #require(ana.id)])
        let page = try fixture.page(for: copies[0])

        #expect(page.groupMeetingPeers.compactMap(\.id) == [fixture.eli])
    }

    @Test("A hidden test student isn't in the Lesson Cohort")
    func cohortLeavesOutHiddenTestStudent() throws {
        let fixture = try Fix1103W1WorkPage.make()
        let testKid = CoreDataTestHelpers.seedStudent(in: fixture.context, firstName: "Test", lastName: "Kid")
        let mine = fixture.work(for: fixture.maya)
        _ = fixture.work(for: fixture.eli)
        _ = fixture.work(for: try #require(testKid.id))
        let page = try fixture.page(for: mine, testStudents: (show: false, names: "Test Kid"))

        #expect(page.lessonCohort.compactMap(\.student.id) == [fixture.eli])
    }

    @Test("A classmate's own project work on the lesson doesn't put her in this child's Project Group")
    func projectGroupIsOnlyTheSameRow() throws {
        let fixture = try Fix1103W1WorkPage.make()
        let mine = fixture.work(for: fixture.maya, kind: .research)
        let elis = fixture.work(for: fixture.eli, kind: .research)
        elis.createdAt = AppCalendar.addingDays(-9, to: Date())
        #expect(CoreDataTestHelpers.save(fixture.context))
        let page = try fixture.page(for: mine)

        #expect(page.projectGroupMembers.isEmpty)
        #expect(page.lessonCohort.compactMap(\.student.id) == [fixture.eli])
    }
}
