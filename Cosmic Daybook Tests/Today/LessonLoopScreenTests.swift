import CoreData
import Foundation
import SwiftUI
import Testing
@testable import CosmicDaybook

/// The lesson loop on screen (plan "Cut unused features and close the lesson
/// loop", Phase 4): Today's "Given — Quick Note" records the lesson and saves
/// a quick note through `QuickNote.save`; the menu command's lesson; the
/// practice warnings' words on Today and in the pickers.
@Suite("Lesson loop on screen")
@MainActor
struct LessonLoopScreenTests {

    struct Class {
        let context: NSManagedObjectContext
        let coordinator: SaveCoordinator
        let first: CDLesson
        let second: CDLesson
        let maya: CDStudent
        let theo: CDStudent
        var mayaID: UUID { maya.id ?? UUID() }
        var theoID: UUID { theo.id ?? UUID() }
    }

    /// Two lessons in Math › Addition, and two children.
    func makeClass() throws -> Class {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let coordinator = SaveCoordinator()
        coordinator.suppressAlerts = true
        let first = CoreDataTestHelpers.seedLesson(
            in: context, name: "Bead Addition", area: "Math", sequence: "Addition"
        )
        first.id = UUID()
        first.orderInSequence = 1
        let second = CoreDataTestHelpers.seedLesson(
            in: context, name: "Stamp Game Addition", area: "Math", sequence: "Addition"
        )
        second.id = UUID()
        second.orderInSequence = 2
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stern")
        let theo = CoreDataTestHelpers.seedStudent(in: context, firstName: "Theo", lastName: "Levi")
        try context.save()
        return Class(context: context, coordinator: coordinator, first: first, second: second, maya: maya, theo: theo)
    }

    func planToday(_ lesson: CDLesson, _ students: [CDStudent], hour: Int = 9, in kids: Class) -> CDLessonAssignment {
        let today = AppCalendar.startOfDay(Date())
        let time = Calendar.current.date(byAdding: .hour, value: hour, to: today) ?? today
        return PresentationFactory.makeScheduled(
            lesson: lesson, students: students, scheduledFor: time, context: kids.context
        )
    }

    func notes(in context: NSManagedObjectContext) -> [CDNote] {
        context.safeFetch(CDFetchRequest(CDNote.self))
    }

    // MARK: - Given — Quick Note

    @Test("Given — Quick Note records the lesson, then saves a quick note on it through QuickNote.save")
    func givenThenQuickNote() throws {
        let kids = try makeClass()
        let assignment = planToday(kids.second, [kids.maya, kids.theo], in: kids)
        try kids.context.save()
        let id = try #require(assignment.id)

        let result = try LessonQuickNote.markGiven(
            assignment, context: kids.context, saveCoordinator: kids.coordinator
        )
        #expect(result.keptOnPlan.isEmpty)
        #expect(assignment.isPresented)
        #expect(LessonQuickNoteTarget.shared.lastGivenID == id)

        #expect(LessonQuickNote.save(
            text: "  Both counted to 40 on their own.  ", presentationID: id, context: kids.context
        ))
        let saved = notes(in: kids.context)
        #expect(saved.count == 1)
        let note = try #require(saved.first)
        #expect(note.body == "Both counted to 40 on their own.")
        #expect(QuickNote.isWaiting(note))
        #expect(note.lessonAssignment === assignment)
        #expect(note.lessonID == assignment.lessonID)
    }

    @Test("Saving nothing, or on a lesson that's gone, leaves no note")
    func saveRefusals() throws {
        let kids = try makeClass()
        let assignment = planToday(kids.first, [kids.maya], in: kids)
        try kids.context.save()
        let id = try #require(assignment.id)

        #expect(!LessonQuickNote.save(text: "   ", presentationID: id, context: kids.context))
        #expect(!LessonQuickNote.save(text: "Counted", presentationID: UUID(), context: kids.context))
        #expect(notes(in: kids.context).isEmpty)
    }

    // MARK: - The command's lesson

    @Test("The command opens on the lesson just given, else the one in progress, else the last one given")
    func commandTarget() throws {
        let kids = try makeClass()
        let given = planToday(kids.first, [kids.maya], hour: 9, in: kids)
        let later = planToday(kids.second, [kids.theo], hour: 11, in: kids)
        try kids.context.save()
        _ = try TodayMarkPresented.record(given, context: kids.context, saveCoordinator: kids.coordinator)
        let givenID = try #require(given.id)
        let laterID = try #require(later.id)

        #expect(LessonQuickNote.target(lastGivenID: givenID, context: kids.context) == givenID)
        // Nothing remembered (or a lesson that isn't there): the one in progress.
        #expect(LessonQuickNote.target(lastGivenID: nil, context: kids.context) == laterID)
        #expect(LessonQuickNote.target(lastGivenID: UUID(), context: kids.context) == laterID)

        // Both given: the one changed last.
        _ = try TodayMarkPresented.record(later, context: kids.context, saveCoordinator: kids.coordinator)
        later.modifiedAt = Date().addingTimeInterval(60)
        try kids.context.save()
        #expect(LessonQuickNote.target(lastGivenID: nil, context: kids.context) == laterID)

        // A lesson given yesterday is not "just given".
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        #expect(LessonQuickNote.target(lastGivenID: givenID, now: yesterday, context: kids.context) == nil)
    }

    // MARK: - Words

    @Test("The practice lines name each earlier lesson once")
    func practiceWords() throws {
        let kids = try makeClass()
        let third = CoreDataTestHelpers.seedLesson(
            in: kids.context, name: "Dot Game", area: "Math", sequence: "Addition"
        )
        third.id = UUID()
        third.orderInSequence = 3
        for (lesson, child) in [(kids.first, kids.mayaID), (kids.first, kids.mayaID), (kids.second, kids.mayaID),
                                (kids.first, kids.theoID)] {
            let work = CoreDataTestHelpers.seedWorkModel(
                in: kids.context, title: lesson.name, studentID: child, lessonID: try #require(lesson.id)
            )
            work.status = .active
        }
        try kids.context.save()
        let found = WorkToShowFirst.find(
            lessonID: try #require(third.id?.uuidString),
            studentIDs: [kids.mayaID, kids.theoID],
            sequences: WorkToShowFirst.Sequences(lessons: [kids.first, kids.second, third]),
            in: kids.context
        )

        #expect(WorkToShowFirst.practicingLine(found[kids.theoID] ?? []) == "Practicing Bead Addition")
        #expect(WorkToShowFirst.practicingLine(found[kids.mayaID] ?? []) == "Practicing Bead Addition and 1 more")
        #expect(WorkToShowFirst.practicingLine([]) == nil)
        let names = [kids.mayaID: "Maya S", kids.theoID: "Theo L"]
        #expect(
            WorkToShowFirst.stillPracticingLine(found, name: { names[$0] ?? "" })
                == "Still practicing: Maya S (Bead Addition and 1 more), Theo L (Bead Addition)"
        )
        #expect(WorkToShowFirst.stillPracticingLine([:], name: { _ in "" }) == nil)
    }

    @Test("Today's rows say who is still practicing, only on lessons not yet given")
    func todayStillPracticing() throws {
        let kids = try makeClass()
        let work = CoreDataTestHelpers.seedWorkModel(
            in: kids.context, title: "Bead Addition", studentID: kids.mayaID, lessonID: try #require(kids.first.id)
        )
        work.status = .active
        let pending = planToday(kids.second, [kids.maya, kids.theo], in: kids)
        let alreadyGiven = planToday(kids.second, [kids.maya], hour: 8, in: kids)
        try kids.context.save()
        _ = try TodayMarkPresented.record(alreadyGiven, context: kids.context, saveCoordinator: kids.coordinator)

        let lines = TodayViewModel.stillPracticingLines(
            for: [pending, alreadyGiven],
            lessons: [kids.first, kids.second],
            names: { $0 == kids.mayaID ? "Maya S" : "Theo L" },
            in: kids.context
        )
        #expect(lines[try #require(pending.id)] == "Still practicing: Maya S (Bead Addition)")
        #expect(lines[try #require(alreadyGiven.id)] == nil)
        // Without the library nothing is read.
        #expect(TodayViewModel.stillPracticingLines(
            for: [pending], lessons: nil, names: { _ in "" }, in: kids.context
        ).isEmpty)
    }

    // MARK: - Groups

    @Test("The Class Grid's Groups button names a ladder the Groups page can draw")
    func groupsRouteFindsTheLadder() throws {
        let kids = try makeClass()
        // As the checklist holds them: the lessons' own area and sequence.
        let route = SequenceLadderRoute(area: kids.first.area, sequence: kids.first.sequence)
        let order = LessonSequenceOrder(lessons: [kids.first, kids.second])
        let ids = [try #require(kids.first.id?.uuidString), try #require(kids.second.id?.uuidString)]
        #expect(order.lessonIDs(area: route.area, sequence: route.sequence) == ids)
        #expect(order.lessonIDs(area: " math", sequence: "ADDITION ") == ids)

        let router = AppRouter()
        router.navigateToGroups(area: route.area, sequence: route.sequence)
        #expect(router.selectedNavItem == .smallSequencePlanner)
        #expect(router.consumePendingSequenceLadder() == route)
        #expect(router.pendingSequenceLadder == nil)
    }

    // MARK: - The picker

    @Test("A child held at check first stays in the Ready run with the reason, and practice shows on every row")
    func pickerCheckFirstAndPracticing() throws {
        let ada = candidate("Ada", "Lin")
        let ben = candidate("Ben", "Ross")
        let cyrus = candidate("Cyrus", "Hale")
        let left = candidate("Dov", "Gray", status: .withdrawn)
        let practicing: [UUID: String] = [ben.id: "Practicing Bead Addition", left.id: "Practicing Bead Addition"]
        let query = StudentPickerModel.Query(
            formerStudents: .shownBlocked,
            arrangement: .selectedThenReady,
            ready: [ada.id],
            checkFirst: [ben.id: "1 piece of work still open"],
            practicing: practicing
        )
        let rows: [StudentPickerRow] = StudentPickerModel.rows(
            candidates: [cyrus, ben, ada, left], query: query, records: [:]
        )

        #expect(rows.map(\.candidate.firstName) == ["Ada", "Ben", "Cyrus", "Dov"])
        var byName: [String: StudentPickerRow] = [:]
        for row in rows { byName[row.candidate.firstName] = row }
        #expect(byName["Ada"]?.isReady == true)
        #expect(byName["Ben"]?.placement == .ready)
        #expect(byName["Ben"]?.isReady == false)
        #expect(byName["Ben"]?.isCheckFirst == true)
        #expect(byName["Ben"]?.checkFirstReason == "1 piece of work still open")
        #expect(byName["Ben"]?.practicing == "Practicing Bead Addition")
        #expect(byName["Cyrus"]?.placement == .everyoneElse)
        #expect(byName["Dov"]?.practicing == nil)

        // A sort-menu picker has no Ready run, but still says who is practicing.
        let sorted = StudentPickerModel.rows(
            candidates: [ben], query: StudentPickerModel.Query(practicing: practicing), records: [:]
        )
        #expect(sorted.first?.practicing == "Practicing Bead Addition")
        #expect(sorted.first?.isCheckFirst == false)
    }

    func candidate(
        _ first: String, _ last: String, status: CDStudent.EnrollmentStatus = .enrolled
    ) -> StudentPickerCandidate {
        StudentPickerCandidate(
            id: UUID(), firstName: first, lastName: last, birthday: nil, level: .upper,
            status: status, departedOn: nil
        )
    }
}
