import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-11-03, the year plan (fix agent S1): a promoted entry follows
// its presentation's day (#20), a lesson given without promotion is drawn once
// (#21), Add Sequence skips lessons she has had (#23), entries are numbered by
// the lesson's own place and old ones repaired (#24), and a child who has left
// gets no new plans (#32).
@Suite("Year plan (bug hunt fixes 11-03, S1)", .serialized)
@MainActor
struct YearPlanFix1103S1 {
    private typealias Fixture = Fix1103S1Fixture

    // MARK: - #20 A moved presentation moves its entry

    @Test("#20 moving a presentation moves the year-plan entry promoted into it")
    func movedPresentationMovesEntry() throws {
        let context = try Fixture.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Levi")
        let lesson = try #require(Fixture.seedSequence([1], in: context).first)
        let firstDay = Fixture.daysFromToday(10)
        let movedDay = Fixture.daysFromToday(14)
        let entry = Fixture.seedEntry(for: ada, lesson: lesson, on: firstDay, in: context)
        let plan = PresentationFactory.makeDraft(lesson: lesson, students: [ada], context: context)
        plan.schedule(for: firstDay)
        #expect(CoreDataTestHelpers.save(context))
        PresentationDropHandling.promoteYearPlanEntries(for: plan, fallbackDate: { firstDay }, context: context)
        #expect(entry.isPromoted)

        // Dragged to another day on the calendar.
        plan.schedule(for: movedDay)
        #expect(CoreDataTestHelpers.save(context))
        PresentationDropHandling.promoteYearPlanEntries(for: plan, fallbackDate: { movedDay }, context: context)

        #expect(entry.isPromoted)
        #expect(entry.plannedDate == movedDay)
    }

    @Test("#20 a promoted entry is drawn on its presentation's day, however the presentation was moved")
    func promotedEntryDrawnOnPresentationDay() throws {
        let context = try Fixture.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Levi")
        let lesson = try #require(Fixture.seedSequence([1], in: context).first)
        let firstDay = Fixture.daysFromToday(10)
        let movedDay = Fixture.daysFromToday(14)
        let entry = Fixture.seedEntry(for: ada, lesson: lesson, on: firstDay, in: context)
        let plan = PresentationFactory.makeDraft(lesson: lesson, students: [ada], context: context)
        plan.schedule(for: firstDay)
        entry.status = .promoted
        entry.promotedAssignmentID = plan.id?.uuidString
        // Moved by a path that doesn't touch the year plan (Claude's reschedule, say).
        plan.schedule(for: movedDay)
        #expect(CoreDataTestHelpers.save(context))

        let vm = StudentYearPlanViewModel()
        vm.load(studentID: ada.id, context: context)

        #expect(vm.items(for: CellID(date: firstDay)).isEmpty)
        let drawn = vm.items(for: CellID(date: movedDay))
        #expect(drawn.count == 1)
        #expect(drawn.first?.planEntry === entry)
    }

    @Test("#20 a draft for two children is scheduled once, and both entries go to that day")
    func groupDraftSchedulesOneDay() throws {
        let context = try Fixture.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Levi")
        let ben = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben", lastName: "Cohen")
        let lesson = try #require(Fixture.seedSequence([1], in: context).first)
        let adaDay = Fixture.daysFromToday(10)
        let benDay = Fixture.daysFromToday(14)
        let adaEntry = Fixture.seedEntry(for: ada, lesson: lesson, on: adaDay, in: context)
        let benEntry = Fixture.seedEntry(for: ben, lesson: lesson, on: benDay, in: context)
        let draft = PresentationFactory.makeDraft(lesson: lesson, students: [ada, ben], context: context)
        #expect(CoreDataTestHelpers.save(context))

        YearPlanPromotionService.autoPromoteIfPlanExists(assignment: draft, context: context)

        let scheduled = try #require(draft.scheduledFor)
        #expect(AppCalendar.startOfDay(scheduled) == adaDay)
        #expect(adaEntry.isPromoted && benEntry.isPromoted)
        #expect(adaEntry.plannedDate == adaDay)
        #expect(benEntry.plannedDate == adaDay)
    }

    // MARK: - #21 Given without promotion, drawn once

    @Test("#21 a lesson given without promoting her entry is drawn once, on the day it was given")
    func givenWithoutPromotionDrawnOnce() throws {
        let context = try Fixture.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Levi")
        let lesson = try #require(Fixture.seedSequence([1], in: context).first)
        let plannedDay = Fixture.daysFromToday(5)
        let givenDay = Fixture.daysFromToday(-1)
        let entry = Fixture.seedEntry(for: ada, lesson: lesson, on: plannedDay, in: context)
        // Quick record or Presented Today: given at once, the entry untouched.
        let given = PresentationFactory.makeScheduled(
            lesson: lesson, students: [ada], scheduledFor: givenDay, context: context
        )
        _ = try LifecycleService.recordPresentation(from: given, presentedAt: givenDay, modelContext: context)
        #expect(CoreDataTestHelpers.save(context))
        #expect(entry.isPlanned)

        let vm = StudentYearPlanViewModel()
        vm.load(studentID: ada.id, context: context)

        #expect(vm.items(for: CellID(date: plannedDay)).isEmpty)
        let drawn = vm.items(for: CellID(date: givenDay))
        #expect(drawn.count == 1)
        #expect(drawn.first?.displayStatus == .given)
        #expect(entry.isPromoted)
        #expect(entry.promotedAssignmentID == given.id?.uuidString)
    }

    // MARK: - #23 Add Sequence skips what she has had

    @Test("#23 Add Sequence starts after a lesson she mastered on the Checklist and leaves it out")
    func addSequenceSkipsMasteredLesson() async throws {
        let context = try Fixture.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Levi")
        let lessons = Fixture.seedSequence([1, 2, 3], in: context)
        // The Checklist's Mastered: a history row and no presentation.
        let mark = CDLessonPresentation(context: context)
        mark.studentID = try #require(ada.id).uuidString
        mark.lessonID = try #require(lessons[0].id).uuidString
        mark.state = .proficient
        mark.masteredAt = Fixture.daysFromToday(-20)
        #expect(CoreDataTestHelpers.save(context))

        let vm = AddSequenceViewModel()
        vm.selectSequence(area: "Math", sequence: "Golden Beads", student: ada, context: context)
        #expect(vm.selectedLesson?.id == lessons[1].id)

        // Picking the mastered lesson by hand still leaves it out, and the
        // first lesson she hasn't had takes the start date.
        vm.selectedLesson = lessons[0]
        vm.startDate = Fixture.daysFromToday(7)
        await vm.computePreview(student: ada, context: context)
        #expect(vm.previewItems.map(\.id) == [lessons[1].id, lessons[2].id].compactMap { $0 })
        let start = YearPlanPacing.schoolDay(onOrAfter: Fixture.daysFromToday(7), in: context)
        #expect(vm.previewItems.first?.date == start)
    }

    // MARK: - #24 Numbered by the lesson's own place

    @Test("#24 Add Sequence numbers entries by the lessons' own order, wherever it starts")
    func addSequenceStoresLessonOrder() async throws {
        let context = try Fixture.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Levi")
        let lessons = Fixture.seedSequence([4, 5, 6], in: context)
        #expect(CoreDataTestHelpers.save(context))

        let vm = AddSequenceViewModel()
        vm.selectedLesson = lessons[1]
        vm.startDate = Fixture.daysFromToday(7)
        await vm.computePreview(student: ada, context: context)
        vm.scheduleAll(student: ada, context: context)

        let byLesson = Dictionary(
            Fixture.entries(for: ada, in: context).map { ($0.lessonID, $0.orderInSequence) },
            uniquingKeysWith: { first, _ in first }
        )
        #expect(byLesson[try #require(lessons[1].id).uuidString] == 5)
        #expect(byLesson[try #require(lessons[2].id).uuidString] == 6)
    }

    @Test("#24 entries from two Add Sequence runs are renumbered on load, once, and a drag moves the right ones")
    func oldEntriesAreRenumbered() async throws {
        let context = try Fixture.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Levi")
        let lessons = Fixture.seedSequence([1, 2, 3, 4], in: context)
        // Two runs: lessons 1–2 numbered 0, 1 and lessons 3–4 numbered 0, 1 again.
        let planned = [
            Fixture.seedEntry(for: ada, lesson: lessons[0], on: Fixture.daysFromToday(60), order: 0, in: context),
            Fixture.seedEntry(for: ada, lesson: lessons[1], on: Fixture.daysFromToday(63), order: 1, in: context),
            Fixture.seedEntry(for: ada, lesson: lessons[2], on: Fixture.daysFromToday(66), order: 0, in: context),
            Fixture.seedEntry(for: ada, lesson: lessons[3], on: Fixture.daysFromToday(69), order: 1, in: context)
        ]
        #expect(CoreDataTestHelpers.save(context))

        let vm = StudentYearPlanViewModel()
        vm.load(studentID: ada.id, context: context)
        #expect(planned.map(\.orderInSequence) == [1, 2, 3, 4])
        #expect(!context.hasChanges)

        // A second load finds nothing to repair and writes nothing.
        let stamps = planned.map(\.modifiedAt)
        vm.load(studentID: ada.id, context: context)
        #expect(planned.map(\.modifiedAt) == stamps)
        #expect(!context.hasChanges)

        // Dragging lesson 1 later moves every lesson after it, lesson 3 included.
        let landing = Fixture.daysFromToday(100)
        await vm.rescheduleWithCascade(
            planned[0], to: landing, studentID: try #require(ada.id), context: context
        )
        let dates = planned.compactMap(\.plannedDate)
        #expect(dates.count == 4)
        #expect(dates[0] >= landing)
        #expect(dates[1] > dates[0])
        #expect(dates[2] > dates[1])
        #expect(dates[3] > dates[2])
    }

    // MARK: - #32 A child who has left

    @Test("#32 Add Sequence plans nothing for a child who has left")
    func addSequenceRefusesDepartedChild() async throws {
        let context = try Fixture.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Ada", lastName: "Levi", enrollmentStatus: .withdrawn
        )
        let lessons = Fixture.seedSequence([1, 2], in: context)
        #expect(CoreDataTestHelpers.save(context))

        let vm = AddSequenceViewModel()
        vm.selectedLesson = lessons[0]
        vm.startDate = Fixture.daysFromToday(7)
        await vm.computePreview(student: ada, context: context)
        vm.scheduleAll(student: ada, context: context)

        #expect(Fixture.entries(for: ada, in: context).isEmpty)
    }
}
