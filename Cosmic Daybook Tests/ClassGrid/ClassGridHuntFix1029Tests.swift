import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// The Class Grid's four from the 2026-10-29 bug hunt (Part 2, "The classroom"): #10
/// Practicing and Reviewing move her own work, not a classmate's; #12 a year-plan entry
/// is Planned, and the Checklist's plans answer it; #15 the grid hears every import that
/// can move a cell; #16 the Children view counts shared project work.
@Suite("Class Grid hunt fixes 2026-10-29")
@MainActor
struct ClassGridHuntFix1029Tests {

    /// Ada, Bruno, Chava; Math › Decimal 0–1 (Decimal 0 is ready for everyone).
    private struct Fixture {
        let viewModel: ClassAreaChecklistViewModel
        let context: NSManagedObjectContext
        let ada: CDStudent
        let bruno: CDStudent
        let chava: CDStudent
        let decimal: [CDLesson]

        func cell(_ student: CDStudent, _ lesson: CDLesson) throws -> CellIdentifier {
            CellIdentifier(studentID: try #require(student.id), lessonID: try #require(lesson.id))
        }

        func state(_ student: CDStudent, _ lesson: CDLesson) -> StudentChecklistRowState? {
            viewModel.state(for: student, lesson: lesson)
        }

        func works(on lesson: CDLesson) throws -> [CDWorkModel] {
            let request = CDFetchRequest(CDWorkModel.self)
            request.predicate = NSPredicate(format: "lessonID == %@", try #require(lesson.id).uuidString)
            return context.safeFetch(request)
        }

        func assignments(on lesson: CDLesson) throws -> [CDLessonAssignment] {
            let request = CDFetchRequest(CDLessonAssignment.self)
            request.predicate = NSPredicate(format: "lessonID == %@", try #require(lesson.id).uuidString)
            return context.safeFetch(request)
        }
    }

    private func makeFixture(seed: (NSManagedObjectContext, [CDStudent], [CDLesson]) throws -> Void = { _, _, _ in })
        throws -> Fixture {
        let context = try CoreDataTestHelpers.makeContext()
        let students = ["Ada", "Bruno", "Chava"].map {
            CoreDataTestHelpers.seedStudent(in: context, firstName: $0, lastName: "Test")
        }
        let decimal = (0..<2).map { order in
            let lesson = CoreDataTestHelpers.seedLesson(
                in: context, name: "Decimal \(order)", area: "Math", sequence: "Decimal"
            )
            lesson.orderInSequence = Int64(order)
            return lesson
        }
        try seed(context, students, decimal)
        try context.save()

        let suite = "ClassGridHuntFix1029Tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)

        let viewModel = ClassAreaChecklistViewModel()
        viewModel.collapsedSequencesDefaults = defaults
        viewModel.selectedArea = "Math"
        viewModel.loadData(context: context)
        viewModel.applyVisibilityFilter(context: context, show: true, namesRaw: "")
        return Fixture(
            viewModel: viewModel, context: context,
            ada: students[0], bruno: students[1], chava: students[2], decimal: decimal
        )
    }

    // MARK: - #10 Her own work

    @Test("#10: Reviewing moves her own copy, never a classmate's linked copy")
    func reviewingMovesHerOwnCopy() throws {
        var copies: [CDWorkModel] = []
        let fixture = try makeFixture { context, students, lessons in
            copies = try linkedCopies(
                on: lessons[0], statuses: [(students[0], .active), (students[1], .active)], in: context
            )
        }
        let (adas, brunos) = (copies[0], copies[1])
        fixture.viewModel.perform(.markReviewing, on: try fixture.cell(fixture.ada, fixture.decimal[0]),
                                  context: fixture.context)

        #expect(adas.status == .review)
        #expect(brunos.status == .active)
        #expect(try fixture.works(on: fixture.decimal[0]).count == 2)
    }

    @Test("#10: with her own copy closed, Reviewing makes her new work and leaves a classmate's open copy")
    func practicingAfterHerCopyClosed() throws {
        var copies: [CDWorkModel] = []
        let fixture = try makeFixture { context, students, lessons in
            copies = try linkedCopies(
                on: lessons[0], statuses: [(students[0], .done), (students[1], .active)], in: context
            )
        }
        let (adas, brunos) = (copies[0], copies[1])
        let adaID = try #require(fixture.ada.id)
        fixture.viewModel.perform(.markReviewing, on: try fixture.cell(fixture.ada, fixture.decimal[0]),
                                  context: fixture.context)

        // Before the fix the only open row naming Ada, Bruno's, went to Reviewing.
        #expect(brunos.status == .active)
        #expect(adas.status == .done)
        let mine = try fixture.works(on: fixture.decimal[0]).filter {
            $0 !== adas && $0 !== brunos && WorkGrouping.owner(of: $0) == adaID
        }
        #expect(mine.count == 1)
        #expect(mine.first?.status == .review)
    }

    @Test("#10: a shared project row she is on is still hers to move")
    func sharedProjectRowMoves() throws {
        var shared: CDWorkModel?
        let fixture = try makeFixture { context, students, lessons in
            let row = CoreDataTestHelpers.seedWorkModel(
                in: context, studentID: try #require(students[1].id), lessonID: try #require(lessons[0].id)
            )
            row.sourceContextType = .projectSession
            row.status = .active
            for child in students.prefix(2) {
                let participant = CDWorkParticipantEntity(context: context)
                participant.id = UUID()
                participant.studentID = try #require(child.id).uuidString
                participant.work = row
            }
            shared = row
        }
        fixture.viewModel.perform(.markReviewing, on: try fixture.cell(fixture.ada, fixture.decimal[0]),
                                  context: fixture.context)
        #expect(shared?.status == .review)
        #expect(try fixture.works(on: fixture.decimal[0]).count == 1)
    }

    // MARK: - #12 The year plan

    @Test("#12: a planned year-plan entry is Planned, not Ready; a skipped or promoted one is not")
    func yearPlanCountsAsPlanned() throws {
        let fixture = try makeFixture { context, students, lessons in
            try yearPlanEntry(students[0], lessons[0], in: context)
            try yearPlanEntry(students[1], lessons[0], status: .skipped, in: context)
            try yearPlanEntry(students[2], lessons[0], status: .promoted, in: context)
        }
        let ada = try #require(fixture.state(fixture.ada, fixture.decimal[0]))
        #expect(ada.displayStatus == .planned)
        #expect(ada.isOnYearPlan)
        #expect(!ada.isScheduled)
        #expect(fixture.state(fixture.bruno, fixture.decimal[0])?.displayStatus == .ready)
        #expect(fixture.state(fixture.chava, fixture.decimal[0])?.displayStatus == .ready)

        // The row's Plan and the Ready count leave her out.
        let lessonID = try #require(fixture.decimal[0].id)
        let order = fixture.viewModel.students.compactMap(\.id)
        #expect(fixture.viewModel.readyCount(for: lessonID) == 2)
        let draft = try #require(fixture.viewModel.makeReadyDraft(
            lessonID: lessonID, studentOrder: order, context: fixture.context
        ))
        let adaID = try #require(fixture.ada.id)
        #expect(!draft.studentIDs.contains(adaID.uuidString))

        // The card says where the plan is.
        let status = ChecklistCellCardText.status(state: ada, record: .init(), precedingLessonName: nil)
        #expect(status.title == "Planned.")
        #expect(status.detail == "On the year plan.")
    }

    @Test("#12: Add to Inbox on a year-plan cell promotes her entry into the plan; Remove gives it back")
    func addToInboxReusesTheEntry() throws {
        var entry: CDYearPlanEntry?
        let fixture = try makeFixture { context, students, lessons in
            entry = try yearPlanEntry(students[0], lessons[0], in: context)
        }
        let cell = try fixture.cell(fixture.ada, fixture.decimal[0])
        fixture.viewModel.perform(.toggleScheduled, on: cell, context: fixture.context)

        let plans = try fixture.assignments(on: fixture.decimal[0])
        let plan = try #require(plans.first)
        #expect(plans.count == 1)
        #expect(entry?.status == .promoted)
        #expect(entry?.promotedAssignmentID == plan.id?.uuidString)
        // One plan for her, by the rule the Groups page reads.
        let index = PresentationRecordIndex(lessonIDs: [plan.lessonID], in: fixture.context)
        #expect(index.openPlans(lesson: plan.lessonID).count == 1)
        #expect(fixture.state(fixture.ada, fixture.decimal[0])?.displayStatus == .planned)

        fixture.viewModel.perform(.toggleScheduled, on: cell, context: fixture.context)
        #expect(entry?.status == .planned)
        #expect(fixture.state(fixture.ada, fixture.decimal[0])?.displayStatus == .planned)
    }

    @Test("#12: Add to Inbox joining a classmate's draft promotes only her entry")
    func addToInboxPromotesOnlyHers() throws {
        var adas: CDYearPlanEntry?
        var brunos: CDYearPlanEntry?
        let fixture = try makeFixture { context, students, lessons in
            _ = PresentationFactory.makeDraft(
                lessonID: try #require(lessons[0].id), studentIDs: [try #require(students[1].id)], context: context
            )
            brunos = try yearPlanEntry(students[1], lessons[0], in: context)
            adas = try yearPlanEntry(students[0], lessons[0], in: context)
        }
        fixture.viewModel.perform(.toggleScheduled, on: try fixture.cell(fixture.ada, fixture.decimal[0]),
                                  context: fixture.context)
        #expect(try fixture.assignments(on: fixture.decimal[0]).count == 1)
        #expect(adas?.status == .promoted)
        #expect(brunos?.status == .planned)
    }

    @Test("#12: the present sheet's draft answers her entry, and an unused draft gives it back")
    func presentationDraftReusesTheEntry() throws {
        var entry: CDYearPlanEntry?
        let fixture = try makeFixture { context, students, lessons in
            entry = try yearPlanEntry(students[0], lessons[0], in: context)
        }
        let lessonID = try #require(fixture.decimal[0].id)
        let adaID = try #require(fixture.ada.id)
        let draft = try #require(fixture.viewModel.makePresentationDraft(
            lessonID: lessonID, studentIDs: [adaID], context: fixture.context
        ))
        let asMade = ChecklistDraftSnapshot(draft)
        #expect(entry?.status == .promoted)
        #expect(entry?.promotedAssignmentID == draft.id?.uuidString)

        fixture.viewModel.discardUnusedDraft(draft, asMade: asMade, context: fixture.context)
        #expect(try fixture.assignments(on: fixture.decimal[0]).isEmpty)
        #expect(entry?.status == .planned)
    }

    // MARK: - #15 Remote changes

    @Test("#15: recall checks, work participants and year-plan entries from another device refresh the grid")
    func remoteChangesCoverEveryInput() {
        let names = ClassGridChecklistView.remoteRefreshEntityNames
        #expect(names.isSuperset(of: ["LessonRecallCheck", "WorkParticipantEntity", "YearPlanEntry"]))
        // The history processor reports only its own list, so every name must be on it.
        #expect(names.isSubset(of: PersistentHistoryProcessor.presentationEntityNames))
        #expect(ReadyQueueLoader.inputEntities.isSubset(of: PersistentHistoryProcessor.presentationEntityNames))
        #expect(PersistentHistoryProcessor.entityNotices(for: ["LessonRecallCheck"]).presentation)
    }

    // MARK: - #16 The Children view

    @Test("#16: the Children view counts shared project work she doesn't own, not a classmate's copy")
    func childrenViewCountsSharedWork() throws {
        let fixture = try makeFixture { context, students, lessons in
            // A project row Bruno owns, with Ada on it, on Decimal 0.
            let row = CoreDataTestHelpers.seedWorkModel(
                in: context, studentID: try #require(students[1].id), lessonID: try #require(lessons[0].id)
            )
            row.sourceContextType = .projectSession
            row.status = .active
            for child in students.prefix(2) {
                let participant = CDWorkParticipantEntity(context: context)
                participant.id = UUID()
                participant.studentID = try #require(child.id).uuidString
                participant.work = row
            }
            // Linked copies on Decimal 1: Chava's closed, Bruno's open and naming her. Her
            // presentation gives her a card.
            _ = PresentationFactory.makePresented(
                lessonID: try #require(lessons[1].id), studentIDs: [try #require(students[2].id)], context: context
            )
            try linkedCopies(
                on: lessons[1], statuses: [(students[2], .done), (students[1], .active)], in: context
            )
        }
        let model = ClassGridChildrenModel()
        model.loadData(context: fixture.context)

        let ada = try #require(model.studentCards.first { $0.id == fixture.ada.id })
        let adaPills = try #require(ada.subjects.first?.sequences.first?.pills)
        #expect(adaPills.first?.status == .practicing)

        let chava = try #require(model.studentCards.first { $0.id == fixture.chava.id })
        let chavaPills = try #require(chava.subjects.first?.sequences.first?.pills)
        #expect(chavaPills.last?.status == .reviewing)
    }
}

// MARK: - Seeding

private extension ClassGridHuntFix1029Tests {

    /// Linked copies on `lesson`: one row per child, each naming every child, made together.
    @discardableResult
    func linkedCopies(
        on lesson: CDLesson, statuses: [(CDStudent, WorkStatus)], in context: NSManagedObjectContext
    ) throws -> [CDWorkModel] {
        let made = Date()
        let lessonID = try #require(lesson.id)
        let children = try statuses.map { try #require($0.0.id) }
        return try statuses.map { owner, status in
            let row = CoreDataTestHelpers.seedWorkModel(
                in: context, title: lesson.name, studentID: try #require(owner.id), lessonID: lessonID
            )
            row.status = status
            row.createdAt = made
            for child in children {
                let participant = CDWorkParticipantEntity(context: context)
                participant.id = UUID()
                participant.studentID = child.uuidString
                participant.work = row
            }
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
