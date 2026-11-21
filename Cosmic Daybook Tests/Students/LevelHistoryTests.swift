// LevelHistoryTests.swift
// Domain logic review 2026-11-20, A8 (plan "Domain logic fixes", Decision 13):
// every level change is a dated step (`CDLevelChange`), one undone the same
// day leaves no history, and a monthly report reads the level she had that
// month.

import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("Level history (domain logic A8)")
@MainActor
struct LevelHistoryTests {

    private func steps(for student: CDStudent, in context: NSManagedObjectContext) -> [CDLevelChange] {
        let request = CDFetchRequest(CDLevelChange.self)
        request.predicate = NSPredicate(format: "studentID == %@", student.id?.uuidString ?? "")
        return context.safeFetch(request)
    }

    @Test("A level change writes one dated step")
    func changeWritesStep() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Sela", level: .lower)
        #expect(CoreDataTestHelpers.save(context))

        #expect(StudentRepository(context: context).updateStudent(id: try #require(maya.id), level: .upper))

        let step = try #require(steps(for: maya, in: context).first)
        #expect(steps(for: maya, in: context).count == 1)
        #expect(step.fromLevel == .lower)
        #expect(step.toLevel == .upper)
        #expect(step.changedOn == AppCalendar.startOfDay(Date()))
        #expect(maya.previousLevel == .lower)
    }

    @Test("A mis-tap leaves no level history")
    func misTapLeavesNoHistory() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Sela", level: .lower)
        #expect(CoreDataTestHelpers.save(context))
        let repository = StudentRepository(context: context)
        let mayaID = try #require(maya.id)

        repository.updateStudent(id: mayaID, level: .upper)
        #expect(steps(for: maya, in: context).count == 1)
        repository.updateStudent(id: mayaID, level: .lower)

        #expect(steps(for: maya, in: context).isEmpty)
        #expect(maya.level == .lower)
        #expect(maya.previousLevel == nil, "the profile no longer says Promoted")
        #expect(maya.dateLastPromoted == nil)
    }

    @Test("Two taps the same day leave one step, from where she was to where she ended")
    func twoTapsOneStep() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Sela", level: .lower)
        #expect(CoreDataTestHelpers.save(context))
        let repository = StudentRepository(context: context)
        let mayaID = try #require(maya.id)

        repository.updateStudent(id: mayaID, level: .upper)
        repository.updateStudent(id: mayaID, level: .adolescent)

        let all = steps(for: maya, in: context)
        #expect(all.count == 1)
        #expect(all.first?.fromLevel == .lower)
        #expect(all.first?.toLevel == .adolescent)
    }

    @Test("An undo the same day keeps a promotion recorded before the history began")
    func undoKeepsOlderPromotion() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Sela", level: .upper)
        let promoted = AppCalendar.startOfDay(
            AppCalendar.shared.date(from: DateComponents(year: 2025, month: 8, day: 25)) ?? Date()
        )
        maya.previousLevel = .lower
        maya.dateLastPromoted = promoted
        #expect(CoreDataTestHelpers.save(context))
        let repository = StudentRepository(context: context)
        let mayaID = try #require(maya.id)

        repository.updateStudent(id: mayaID, level: .adolescent)
        repository.updateStudent(id: mayaID, level: .upper)

        #expect(maya.level == .upper)
        #expect(maya.previousLevel == .lower)
        #expect(maya.dateLastPromoted == promoted)
    }

    @Test("A monthly report reads the level she had that month")
    func reportReadsThatMonthsLevel() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Sela", level: .upper)
        let step = CDLevelChange(context: context)
        step.studentID = try #require(maya.id).uuidString
        step.fromLevelRaw = CDStudent.Level.lower.rawValue
        step.toLevelRaw = CDStudent.Level.upper.rawValue
        step.changedOn = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))
        #expect(CoreDataTestHelpers.save(context))

        let builder = MonthlyReportContextBuilder(
            context: context, reportService: ReportGeneratorService(), calendar: calendar
        )
        func level(_ month: Int) -> CDStudent.Level {
            builder.buildContext(
                for: maya, month: ReportMonth(year: 2026, month: month), includeStudentReflection: false
            ).level
        }
        #expect(level(9) == .lower)
        #expect(level(10) == .lower, "a change during the month counts from the next one")
        #expect(level(11) == .upper)
    }
}
