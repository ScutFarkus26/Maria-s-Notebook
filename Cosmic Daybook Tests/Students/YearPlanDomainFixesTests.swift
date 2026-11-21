import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Domain-logic review R17 and A16: the year plan's move lives in one shared
/// function Claude calls too, every path that puts a lesson on a day promotes
/// the entry onto that day, the load repairs an entry whose presentation is
/// gone, and Remove skips rather than deletes.
@Suite("Year plan domain fixes (R17, A16)", .serialized)
@MainActor
struct YearPlanDomainFixesTests {
    private typealias Fixture = Fix1103S1Fixture

    private func tools(_ context: NSManagedObjectContext) -> [MCPToolDefinition] {
        MCPNotebookTools.makeTools(context: { context })
    }

    private func tool(_ name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    private func day(_ iso: String) throws -> Date {
        AppCalendar.startOfDay(try CoreDataTestHelpers.day(iso))
    }

    // MARK: - R17: Claude's move cascades

    @Test("Claude's year-plan move shifts the lessons after it, keeping their spacing")
    func claudesMoveShiftsSuccessors() async throws {
        let context = try Fixture.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Levi")
        let lessons = Fixture.seedSequence([0, 1, 2], in: context)
        let entries = [
            Fixture.seedEntry(for: ada, lesson: lessons[0], on: try day("2027-01-11"), order: 0, in: context),
            Fixture.seedEntry(for: ada, lesson: lessons[1], on: try day("2027-01-14"), order: 1, in: context),
            Fixture.seedEntry(for: ada, lesson: lessons[2], on: try day("2027-01-19"), order: 2, in: context)
        ]
        #expect(CoreDataTestHelpers.save(context))

        let receipt = try await tool("update_year_plan_entry", in: tools(context)).handler([
            "entry_id": .string(try #require(entries[0].id).uuidString),
            "target_date": .string("2027-02-01")
        ])

        let dates = entries.compactMap(\.plannedDate)
        #expect(dates.count == 3)
        #expect(dates[0] == (try day("2027-02-01")))
        #expect(dates[1] > dates[0])
        #expect(dates[2] > dates[1])
        #expect(receipt.contains("2 later lessons"))
        #expect(!context.hasChanges)
    }

    @Test("the year plan's own drag and Claude's move land the lessons after it on the same days")
    func screenAndClaudeAgree() async throws {
        func plan(_ context: NSManagedObjectContext) throws -> (CDStudent, [CDYearPlanEntry]) {
            let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Levi")
            let lessons = Fixture.seedSequence([0, 1, 2], in: context)
            let entries = [
                Fixture.seedEntry(for: ada, lesson: lessons[0], on: try day("2027-01-11"), order: 0, in: context),
                Fixture.seedEntry(for: ada, lesson: lessons[1], on: try day("2027-01-14"), order: 1, in: context),
                Fixture.seedEntry(for: ada, lesson: lessons[2], on: try day("2027-01-19"), order: 2, in: context)
            ]
            #expect(CoreDataTestHelpers.save(context))
            return (ada, entries)
        }
        let screenContext = try Fixture.makeContext()
        let (ada, onScreen) = try plan(screenContext)
        let vm = StudentYearPlanViewModel()
        vm.load(studentID: ada.id, context: screenContext)
        await vm.rescheduleWithCascade(
            onScreen[0], to: try day("2027-02-01"), studentID: try #require(ada.id), context: screenContext
        )

        let claudeContext = try Fixture.makeContext()
        let (_, byClaude) = try plan(claudeContext)
        _ = try await tool("update_year_plan_entry", in: tools(claudeContext)).handler([
            "entry_id": .string(try #require(byClaude[0].id).uuidString),
            "target_date": .string("2027-02-01")
        ])

        #expect(onScreen.map(\.plannedDate) == byClaude.map(\.plannedDate))
    }

    // MARK: - R17: dated promotion

    @Test("schedule_presentation promotes her entry onto the day it was scheduled for")
    func scheduleUsesDatedPromotion() async throws {
        let context = try Fixture.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Levi")
        let lesson = Fixture.seedSequence([0], in: context)[0]
        let entry = Fixture.seedEntry(for: ada, lesson: lesson, on: try day("2027-01-11"), in: context)
        #expect(CoreDataTestHelpers.save(context))

        _ = try await tool("schedule_presentation", in: tools(context)).handler([
            "lesson": .string(try #require(lesson.id).uuidString),
            "student_names": .array([.string("Ada Levi")]),
            "date": .string("2027-01-20")
        ])

        #expect(entry.status == .promoted)
        #expect(entry.plannedDate == (try day("2027-01-20")))
    }

    @Test("a child added to a plan over Claude has her entry promoted onto its day")
    func rosterAddPromotes() async throws {
        let context = try Fixture.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Levi")
        let leo = CoreDataTestHelpers.seedStudent(in: context, firstName: "Leo", lastName: "Marsh")
        let lesson = Fixture.seedSequence([0], in: context)[0]
        let plan = PresentationFactory.makeDraft(lesson: lesson, students: [ada], context: context)
        plan.schedule(onDay: try day("2027-01-20"))
        let entry = Fixture.seedEntry(for: leo, lesson: lesson, on: try day("2027-01-11"), in: context)
        #expect(CoreDataTestHelpers.save(context))

        _ = try await tool("update_presentation_roster", in: tools(context)).handler([
            "presentation_id": .string(try #require(plan.id).uuidString),
            "add_students": .array([.string("Leo Marsh")])
        ])

        #expect(entry.status == .promoted)
        #expect(entry.promotedAssignmentID == plan.id?.uuidString)
        #expect(entry.plannedDate == (try day("2027-01-20")))
    }

    // MARK: - R17: the repair

    @Test("an entry promoted into a presentation that no longer exists goes back to planned on load")
    func orphanedPromotionIsRepaired() throws {
        let context = try Fixture.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Levi")
        let lessons = Fixture.seedSequence([0, 1, 2], in: context)
        let orphan = Fixture.seedEntry(for: ada, lesson: lessons[0], on: try day("2027-01-11"), in: context)
        orphan.status = .promoted
        orphan.promotedAssignmentID = UUID().uuidString
        orphan.modifiedAt = Date(timeIntervalSinceNow: -3 * 86_400)
        // Changed within the day: its presentation may still be syncing in, so it waits.
        let recent = Fixture.seedEntry(for: ada, lesson: lessons[2], on: try day("2027-01-18"), order: 2, in: context)
        let recentLink = UUID().uuidString
        recent.status = .promoted
        recent.promotedAssignmentID = recentLink
        recent.modifiedAt = Date()
        // Promoted into an undated draft that is still in the Inbox: it stays.
        let draft = PresentationFactory.makeDraft(lesson: lessons[1], students: [ada], context: context)
        let kept = Fixture.seedEntry(for: ada, lesson: lessons[1], on: try day("2027-01-14"), order: 1, in: context)
        kept.status = .promoted
        kept.promotedAssignmentID = draft.id?.uuidString
        #expect(CoreDataTestHelpers.save(context))

        let vm = StudentYearPlanViewModel()
        vm.load(studentID: ada.id, context: context)

        #expect(orphan.status == .planned)
        #expect(orphan.promotedAssignmentID == nil)
        #expect(kept.status == .promoted)
        #expect(kept.promotedAssignmentID == draft.id?.uuidString)
        #expect(recent.status == .promoted)
        #expect(recent.promotedAssignmentID == recentLink)
        #expect(!context.hasChanges)
    }

    @Test("the launch step renumbers tied lessons, then puts every child's entries right, and saves")
    func launchStepRepairsTheWholeNotebook() throws {
        let context = try Fixture.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Levi")
        let lessons = Fixture.seedSequence([0, 1, 1], in: context)
        for (index, lesson) in lessons.enumerated() { lesson.sortIndex = Int64(index) }
        let tied = Fixture.seedEntry(for: ada, lesson: lessons[2], on: try day("2027-01-19"), order: 1, in: context)
        let orphan = Fixture.seedEntry(for: ada, lesson: lessons[0], on: try day("2027-01-11"), in: context)
        orphan.status = .promoted
        orphan.promotedAssignmentID = UUID().uuidString
        orphan.modifiedAt = Date(timeIntervalSinceNow: -3 * 86_400)
        #expect(CoreDataTestHelpers.save(context))

        #expect(YearPlanEntryRepair.repairAllAndSave(in: context) == 2)

        #expect(lessons.map(\.orderInSequence) == [0, 1, 2])
        #expect(tied.orderInSequence == 2)
        #expect(orphan.status == .planned)
        #expect(orphan.promotedAssignmentID == nil)
        #expect(!context.hasChanges)
        #expect(YearPlanEntryRepair.repairAllAndSave(in: context) == 0)
    }

    // MARK: - A16: Remove skips

    @Test("Remove on the year-plan calendar skips the entry and keeps it")
    func removeSkips() throws {
        let context = try Fixture.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Levi")
        let lesson = Fixture.seedSequence([0], in: context)[0]
        let entry = Fixture.seedEntry(for: ada, lesson: lesson, on: try day("2027-01-11"), in: context)
        #expect(CoreDataTestHelpers.save(context))

        let vm = StudentYearPlanViewModel()
        vm.load(studentID: ada.id, context: context)
        vm.removeEntry(entry, context: context)

        #expect(!entry.isDeleted)
        #expect(entry.managedObjectContext != nil)
        #expect(entry.status == .skipped)
        #expect(Fixture.entries(for: ada, in: context).count == 1)
        #expect(!context.hasChanges)
    }
}
