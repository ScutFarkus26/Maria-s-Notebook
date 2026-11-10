import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The Class Grid's Brewing mark (plan: Brewing mark in the Class Grid, 2026-11-10): a
/// cell planned by an undated Inbox lesson says when that lesson sits under Brewing in
/// Lessons & Work. The grid asks the Inbox's own rule (`InboxPlacement`), so these pin
/// the flag, who it names, and that the grid and the Inbox agree.
@Suite("Checklist Brewing mark")
@MainActor
struct ChecklistBrewingTests {

    typealias Cell = CellIdentifier
    typealias Room = ChecklistBrewingRoom

    // MARK: - 1 to 6: When a Cell Is Brewing

    @Test("1: an undated plan whose lesson before wasn't given is brewing, held by her")
    func undatedPlanBeforeNotGiven() throws {
        let room = try Room.make()
        room.plan([room.avital])
        try room.context.save()

        let state = try room.state(room.avital)
        #expect(state.displayStatus == .planned)
        #expect(state.isInboxPlan)
        #expect(state.isBrewing)
        #expect(state.showsBrewing)
        #expect(state.brewingHeldBy == [try #require(room.avital.id)])
        // The children not on the plan are untouched.
        #expect(try room.state(room.dalia).isBrewing == false)
    }

    @Test("2: the lesson before mastered is Planned, not brewing")
    func beforeMastered() throws {
        let room = try Room.make()
        let mark = CDLessonPresentation(context: room.context)
        mark.studentID = room.avital.cloudKitKey
        mark.lessonID = try #require(room.before.id).uuidString
        mark.state = .proficient
        mark.masteredAt = try CoreDataTestHelpers.day("2026-11-02")
        room.plan([room.avital])
        try room.context.save()

        let state = try room.state(room.avital)
        #expect(state.displayStatus == .planned)
        #expect(!state.isBrewing)
        #expect(state.brewingHeldBy.isEmpty)
    }

    @Test("2: the lesson before given with both gates off is Planned, not brewing")
    func beforeGivenWithBothGatesOff() throws {
        let room = try Room.make()
        room.before.practiceOverride = .no
        room.before.confirmationOverride = .no
        try room.give([room.avital])
        room.plan([room.avital])
        try room.context.save()

        let state = try room.state(room.avital)
        #expect(state.displayStatus == .planned)
        #expect(!state.isBrewing)

        // The same giving under the built-in rules still waits on the guide's confirmation.
        room.before.practiceOverride = .inherit
        room.before.confirmationOverride = .inherit
        try room.context.save()
        #expect(try room.state(room.avital).isBrewing)
    }

    @Test("3: a group of three where one isn't ready: all three brewing, held by the one")
    func groupHeldByOne() throws {
        let room = try Room.make()
        try room.give([room.avital, room.maya], confirming: [room.avital, room.maya])
        room.plan([room.maya, room.dalia, room.avital])
        try room.context.save()

        let daliaID = try #require(room.dalia.id)
        for student in [room.avital, room.dalia, room.maya] {
            let state = try room.state(student)
            #expect(state.showsBrewing)
            #expect(state.brewingHeldBy == [daliaID])
        }
    }

    @Test("3: the children holding a group come in roster order")
    func heldByInRosterOrder() throws {
        let room = try Room.make()
        try room.give([room.dalia], confirming: [room.dalia])
        room.plan([room.maya, room.dalia, room.avital])
        try room.context.save()

        #expect(try room.state(room.dalia).brewingHeldBy == [try #require(room.avital.id), try #require(room.maya.id)])
    }

    @Test("4: a plan the guide unlocked isn't brewing")
    func manuallyUnblocked() throws {
        let room = try Room.make()
        let plan = room.plan([room.avital])
        plan.manuallyUnblocked = true
        try room.context.save()

        let state = try room.state(room.avital)
        #expect(state.displayStatus == .planned)
        #expect(!state.isBrewing)
    }

    @Test("5: a dated plan isn't brewing, alone or beside an undated one")
    func datedPlan() throws {
        let room = try Room.make()
        let dated = room.plan([room.avital])
        dated.schedule(onDay: try CoreDataTestHelpers.day("2026-11-12"))
        try room.context.save()
        #expect(try room.state(room.avital).displayStatus == .planned)
        #expect(try room.state(room.avital).isBrewing == false)

        // She is on an Inbox lesson too, and it is brewing; the dated plan wins.
        room.plan([room.avital, room.dalia])
        try room.context.save()
        #expect(try room.state(room.avital).isBrewing == false)
        #expect(try room.state(room.dalia).isBrewing)
    }

    @Test("5: a year-plan entry alone is Planned, not brewing")
    func yearPlanEntryAlone() throws {
        let room = try Room.make()
        // Given, not confirmed: an Inbox lesson would brew, a year-plan entry doesn't.
        try room.give([room.avital])
        let entry = CDYearPlanEntry(context: room.context)
        entry.studentID = room.avital.cloudKitKey
        entry.lessonID = try #require(room.planned.id).uuidString
        entry.sequenceGroupKey = "Math::Decimal"
        entry.status = .planned
        try room.context.save()

        let state = try room.state(room.avital)
        #expect(state.displayStatus == .planned)
        #expect(!state.isScheduled)
        #expect(!state.isBrewing)
    }

    @Test("6: a withdrawn or hidden child on the lesson doesn't hold it")
    func judgedSet() async throws {
        let room = try Room.make()
        let left = CoreDataTestHelpers.seedStudent(
            in: room.context, firstName: "Leah", lastName: "Hart", enrollmentStatus: .withdrawn
        )
        let hidden = CoreDataTestHelpers.seedStudent(in: room.context, firstName: "Test", lastName: "Child")
        try room.give([room.avital], confirming: [room.avital])
        let plan = room.plan([room.avital, left, hidden])
        try room.context.save()

        // Hidden: neither of them is judged, and Avital is ready.
        let grid = try room.grid(showTestStudents: false, testNames: "Test Child")
        let state = try #require(grid.state(for: room.avital, lesson: room.planned))
        #expect(state.displayStatus == .planned)
        #expect(!state.isBrewing)
        let inbox = await Room.inbox(room.context, showTestStudents: false, testNames: "Test Child")
        #expect(inbox.readyLessons.contains(plan))

        // Shown again, the test child holds it; the withdrawn child still doesn't.
        let shown = try #require(try room.grid().state(for: room.avital, lesson: room.planned))
        #expect(shown.isBrewing)
        #expect(shown.brewingHeldBy == [try #require(hidden.id)])
        let inboxShown = await Room.inbox(room.context)
        #expect(inboxShown.blockedLessons.contains(plan))
    }

    // MARK: - 9: The Key's Counts

    @Test("9: Planned and Brewing in the key add up to the cells that are Planned")
    func counts() throws {
        let room = try Room.make()
        // Decimal 1 brews for two children; Decimal 0 starts the sub-area, so its plan is ready.
        room.plan([room.avital, room.dalia])
        room.plan([room.maya], of: room.before)
        try room.context.save()

        let counts = try room.grid().statusCounts
        #expect(counts[.planned] == 3)
        #expect(counts.brewing == 2)
        #expect(ChecklistStatusBar.count(of: .planned, in: counts) == 1)
        #expect(ChecklistStatusBar.count(of: .planned, in: counts) + counts.brewing == counts[.planned])
        #expect(counts.total == 9)
    }

    @Test("9: a child already given the lesson, on a brewing plan to give it again, isn't counted as Brewing")
    func presentedCellKeepsItsRung() throws {
        let room = try Room.make()
        let given = PresentationFactory.makeDraft(lesson: room.planned, students: [room.avital], context: room.context)
        given.markPresented(at: try CoreDataTestHelpers.day("2026-11-03"), snapshotLesson: false)
        room.plan([room.avital])
        try room.context.save()

        let state = try room.state(room.avital)
        #expect(state.displayStatus == .presented)
        #expect(state.isBrewing)
        #expect(!state.showsBrewing)
        #expect(try room.grid().statusCounts.brewing == 0)
    }

    // MARK: - 10: Wording

    private func brewingState(heldBy: [UUID]) -> StudentChecklistRowState {
        StudentChecklistRowState(
            lessonID: UUID(), plannedItemID: UUID(), presentationLogID: nil, contractID: nil,
            isScheduled: true, isPresented: false, isActive: false, isComplete: false,
            lastActivityDate: nil, isStale: false, isInboxPlan: true,
            blockingReason: .prerequisiteNotPresented, isBrewing: true, brewingHeldBy: heldBy
        )
    }

    @Test("10: the card says Brewing and what the lesson is waiting on")
    func cardWording() {
        let state = brewingState(heldBy: [UUID()])
        let text = { (others: [String]) in
            ChecklistCellCardText.status(
                state: state, record: .init(), precedingLessonName: "Decimal 0", brewingHeldByOthers: others
            )
        }
        // Held by her.
        #expect(text([]) == .init(
            title: "Brewing.", detail: "In the Inbox under Brewing, waiting on Decimal 0."
        ))
        // Held by others.
        #expect(text(["Avital B", "Dalia K", "Maya S"]).detail
            == "In the Inbox under Brewing, waiting on Avital B and 2 others for Decimal 0.")
        #expect(text(["Avital B", "Dalia K"]).detail
            == "In the Inbox under Brewing, waiting on Avital B and 1 other for Decimal 0.")
        #expect(text(["Avital B"]) == .init(
            title: "Brewing.", detail: "In the Inbox under Brewing, waiting on Avital B for Decimal 0."
        ))
    }

    @Test("10: a ready Inbox plan says which tab it is under")
    func readyInboxPlanWording() {
        let ready = StudentChecklistRowState(
            lessonID: UUID(), plannedItemID: UUID(), presentationLogID: nil, contractID: nil,
            isScheduled: true, isPresented: false, isActive: false, isComplete: false,
            lastActivityDate: nil, isStale: false, isInboxPlan: true
        )
        #expect(ChecklistCellCardText.status(state: ready, record: .init(), precedingLessonName: "Decimal 0")
            == .init(title: "Planned.", detail: "In the Inbox, under Ready."))
        #expect(ChecklistCellDescription.summary(state: ready, precedingLessonName: "Decimal 0") == "Planned")
    }

    @Test("10: hover text and VoiceOver say Brewing and name the lesson before")
    func hoverAndVoiceOverWording() {
        let state = brewingState(heldBy: [UUID()])
        #expect(ChecklistCellDescription.helpText(
            studentName: "Maya S", lessonName: "Decimal 1", state: state, precedingLessonName: "Decimal 0"
        ) == "Maya S · Decimal 1 — Brewing: waiting on Decimal 0")
        #expect(ChecklistCellDescription.accessibilityValue(state: state, precedingLessonName: "Decimal 0")
            == "Brewing: waiting on Decimal 0")
        // With no name to give, it still says where the lesson is.
        #expect(ChecklistCellDescription.summary(state: state, precedingLessonName: nil) == "Brewing")

        #expect(ChecklistMark.label(status: .planned, recall: nil, brewing: true) == "Brewing")
        #expect(ChecklistMark.label(status: .planned, recall: nil) == "Planned")
        // Only a Planned mark is ever Brewing.
        #expect(ChecklistMark.label(status: .presented, recall: nil, brewing: true) == "Presented")
    }
}

/// Avital B, Dalia K and Maya S (roster order); Math › Decimal 0, 1 and 2 with the
/// built-in rules (practice and the guide's confirmation both required).
@MainActor
struct ChecklistBrewingRoom {
    let stack: CoreDataStack
    let avital: CDStudent
    let dalia: CDStudent
    let maya: CDStudent
    let lessons: [CDLesson]

    var context: NSManagedObjectContext { stack.viewContext }
    /// Decimal 0: the lesson before.
    var before: CDLesson { lessons[0] }
    /// Decimal 1: the lesson the tests plan.
    var planned: CDLesson { lessons[1] }

    static func make() throws -> ChecklistBrewingRoom {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let avital = CoreDataTestHelpers.seedStudent(in: context, firstName: "Avital", lastName: "Berg")
        let dalia = CoreDataTestHelpers.seedStudent(in: context, firstName: "Dalia", lastName: "Katz")
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        let lessons = (0..<3).map { order in
            let lesson = CoreDataTestHelpers.seedLesson(
                in: context, name: "Decimal \(order)", area: "Math", sequence: "Decimal"
            )
            lesson.orderInSequence = Int64(order)
            return lesson
        }
        try context.save()
        return ChecklistBrewingRoom(stack: stack, avital: avital, dalia: dalia, maya: maya, lessons: lessons)
    }

    /// An undated, not-given plan: a row in the Inbox.
    @discardableResult
    func plan(_ students: [CDStudent], of lesson: CDLesson? = nil) -> CDLessonAssignment {
        PresentationFactory.makeDraft(lesson: lesson ?? planned, students: students, context: context)
    }

    /// A given presentation of Decimal 0.
    @discardableResult
    func give(_ students: [CDStudent], confirming: [CDStudent] = []) throws -> CDLessonAssignment {
        let given = PresentationFactory.makeDraft(lesson: before, students: students, context: context)
        given.markPresented(at: try CoreDataTestHelpers.day("2026-11-02"), snapshotLesson: false)
        for student in confirming {
            given.confirmStudent(try #require(student.id))
        }
        return given
    }

    /// The Checklist's own view model over Math, as the screen builds it.
    func grid(showTestStudents: Bool = true, testNames: String = "") throws -> ClassAreaChecklistViewModel {
        try Self.grid(
            area: "Math", context: context, showTestStudents: showTestStudents, testNames: testNames
        )
    }

    func state(_ student: CDStudent, _ lesson: CDLesson? = nil) throws -> StudentChecklistRowState {
        try #require(try grid().state(for: student, lesson: lesson ?? planned))
    }

    static func grid(
        area: String, context: NSManagedObjectContext, showTestStudents: Bool = true, testNames: String = ""
    ) throws -> ClassAreaChecklistViewModel {
        let viewModel = ClassAreaChecklistViewModel()
        let suite = "ChecklistBrewingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        viewModel.collapsedSequencesDefaults = defaults
        viewModel.selectedArea = area
        viewModel.loadData(context: context)
        viewModel.applyVisibilityFilter(context: context, show: showTestStudents, namesRaw: testNames)
        return viewModel
    }

    /// Lessons & Work's Inbox over the same store.
    static func inbox(
        _ context: NSManagedObjectContext, showTestStudents: Bool = true, testNames: String = ""
    ) async -> PresentationsViewModel {
        let viewModel = PresentationsViewModel()
        viewModel.update(
            viewContext: context,
            calendar: AppCalendar.shared,
            inboxOrderRaw: "",
            showTestStudents: showTestStudents,
            testStudentNamesRaw: testNames,
            lessons: context.safeFetch(CDFetchRequest(CDLesson.self)),
            students: context.safeFetch(CDFetchRequest(CDStudent.self))
        )
        await viewModel.pendingUpdateTask?.value
        return viewModel
    }
}
