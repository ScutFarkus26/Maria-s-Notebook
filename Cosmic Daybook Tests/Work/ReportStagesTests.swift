import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// A report's five stages (2026-10-30): the steps are the stages, linked
// copies move together, and Presented is the report closed as Finished.
@Suite("Report Stages")
@MainActor
struct ReportStagesTests {

    private func startReport(
        _ title: String = "Squishies", children: Int = 2, in context: NSManagedObjectContext
    ) throws -> [CDWorkModel] {
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Research Report", area: "Language")
        let copies = try ReportStages.startReport(
            title: title, studentIDs: (0..<children).map { _ in UUID() },
            lessonID: try #require(lesson.id), context: context
        )
        #expect(CoreDataTestHelpers.save(context))
        return copies
    }

    private func ticked(_ work: CDWorkModel) -> [Bool] {
        work.orderedSteps.map(\.isCompleted)
    }

    @Test("Starting a report makes a linked copy for each child, at Topic")
    func startReportMakesLinkedCopiesAtTopic() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let copies = try startReport(in: context)

        #expect(copies.count == 2)
        for copy in copies {
            #expect(copy.kind == .report)
            #expect(copy.title == "Squishies")
            #expect(ReportStages.titles(of: copy) == ReportStages.standardTitles)
            #expect(ReportStages.currentStage(of: copy) == 0)
            #expect(ReportStages.stageName(of: copy) == "Topic")
        }
        #expect(WorkGrouping.group(containing: copies[0], in: context).members.count == 2)
    }

    @Test("Setting a stage ticks the ones before it and unticks it and the ones after")
    func settingAStageTicksEarlierAndUnticksLater() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let report = try startReport(children: 1, in: context)[0]
        let monday = AppCalendar.addingDays(-3, to: Date())

        _ = ReportStages.set(stage: 2, on: [report], day: monday, context: context)
        #expect(ticked(report) == [true, true, false, false, false])
        #expect(ReportStages.currentStage(of: report) == 2)

        _ = ReportStages.set(stage: 1, on: [report], context: context)
        #expect(ticked(report) == [true, false, false, false, false])
        // A stage passed earlier keeps the day it was passed.
        #expect(report.orderedSteps[0].completedAt == AppCalendar.startOfDay(monday))
    }

    @Test("A stage set on one copy is set on every linked copy")
    func stageMovesEveryLinkedCopy() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let copies = try startReport(in: context)

        #expect(ReportStages.setStage(2, of: copies[0], context: context))
        #expect(ReportStages.currentStage(of: copies[1]) == 2)
        #expect(ReportStages.stageName(of: copies[1]) == "Writing")
    }

    @Test("Presented closes every copy as Finished, and an earlier stage reopens them")
    func presentedClosesAsFinishedAndMovingBackReopens() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let copies = try startReport(in: context)

        #expect(ReportStages.setStage(4, of: copies[0], context: context))
        for copy in copies {
            #expect(copy.status == .done)
            #expect(ReportStages.currentStage(of: copy) == nil)
            #expect(ReportStages.stageName(of: copy) == "Presented")
        }

        #expect(ReportStages.setStage(3, of: copies[1], context: context))
        for copy in copies {
            #expect(copy.status == .active)
            #expect(ReportStages.currentStage(of: copy) == 3)
        }
    }

    @Test("A copy closed another way (she dropped the report) is left as it is")
    func aCopyClosedAnotherWayStaysPut() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let copies = try startReport(in: context)
        try WorkLogService.log([.init(work: copies[1], status: .incomplete)], context: context)

        #expect(ReportStages.setStage(4, of: copies[0], context: context))
        #expect(copies[0].status == .done)
        #expect(copies[1].status == .incomplete)
        #expect(ticked(copies[1]) == [false, false, false, false, false])
    }

    @Test("A report with no steps reads as Topic and gets the five when its stage is set")
    func reportWithNoStepsGetsTheFive() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let report = CoreDataTestHelpers.seedWorkModel(in: context, title: "Trampolines")
        report.kind = .report
        #expect(CoreDataTestHelpers.save(context))

        #expect(ReportStages.titles(of: report) == ReportStages.standardTitles)
        #expect(ReportStages.currentStage(of: report) == 0)
        #expect(ReportStages.setStage(1, of: report, context: context))
        #expect(report.orderedSteps.map(\.title) == ReportStages.standardTitles)
        #expect(ticked(report) == [true, false, false, false, false])
    }

    @Test("A report's own steps are its stages, and its last one closes it")
    func ownStepsAreKept() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let report = CoreDataTestHelpers.seedWorkModel(in: context, title: "Alaska")
        report.kind = .report
        let service = WorkStepService(context: context)
        for title in ["Questions", "Notes", "Poster"] {
            try service.createStep(for: report, title: title)
        }
        #expect(CoreDataTestHelpers.save(context))

        #expect(ReportStages.titles(of: report) == ["Questions", "Notes", "Poster"])
        #expect(ReportStages.setStage(2, of: report, context: context))
        #expect(report.status == .done)
        #expect(ReportStages.stageName(of: report) == "Poster")
    }

    @Test("Setting a stage outside a meeting ends a rest")
    func settingAStageEndsARest() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let report = try startReport(children: 1, in: context)[0]
        report.restingUntil = AppCalendar.addingDays(10, to: Date())
        #expect(CoreDataTestHelpers.save(context))

        #expect(ReportStages.setStage(1, of: report, context: context))
        #expect(report.restingUntil == nil)
    }

    @Test("The day she presents is one check-in on every copy, moved or skipped, never doubled")
    func presentDayIsOneCheckInOnEveryCopy() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let copies = try startReport(in: context)
        let first = AppCalendar.addingDays(5, to: Date())
        let second = AppCalendar.addingDays(8, to: Date())

        ReportStages.setPresentDay(first, for: copies[0], context: context)
        #expect(CoreDataTestHelpers.save(context))
        for copy in copies {
            #expect(ReportStages.presentDay(of: copy) == AppCalendar.startOfDay(first))
        }

        ReportStages.setPresentDay(second, for: copies[1], context: context)
        #expect(CoreDataTestHelpers.save(context))
        for copy in copies {
            let checkIns = (copy.checkIns?.allObjects as? [CDWorkCheckIn]) ?? []
            #expect(checkIns.count == 1)
            #expect(checkIns.first.map(ReportStages.isPresentDay) == true)
            #expect(ReportStages.presentDay(of: copy) == AppCalendar.startOfDay(second))
        }

        ReportStages.setPresentDay(nil, for: copies[0], context: context)
        #expect(CoreDataTestHelpers.save(context))
        for copy in copies {
            #expect(ReportStages.presentDay(of: copy) == nil)
        }
    }

    @Test("Ticking the day she presents on Today moves the report to Presented")
    func presentDayTickedOnTodayPresentsTheReport() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let copies = try startReport(in: context)
        _ = ReportStages.set(stage: 3, on: copies, context: context)
        ReportStages.setPresentDay(Date(), for: copies[0], context: context)
        #expect(CoreDataTestHelpers.save(context))
        let checkIn = try #require((copies[0].checkIns?.allObjects as? [CDWorkCheckIn])?.first)
        let item = WorkCheckInFollowUp(
            id: try #require(checkIn.id), checkIn: checkIn, work: copies[0],
            dueDay: AppCalendar.startOfDay(Date()), isOverdue: false,
            studentIDs: WorkGrouping.studentIDs(of: copies[0]), departedStudentIDs: []
        )

        try TodayCheckInFollowUpActions.markCheckedIn(item, context: context)

        #expect(copies.allSatisfy { $0.status == .done })
        #expect(copies.allSatisfy { ReportStages.stageName(of: $0) == "Presented" })
        #expect(checkIn.status == .completed)
    }

    @Test("The Reports board folds linked copies into one row, by stage")
    func boardFoldsCopiesByStage() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let squishies = try startReport("Squishies", in: context)
        let fossils = try startReport("Fossils", children: 1, in: context)
        let parakeets = try startReport("Parakeets", children: 1, in: context)
        let alaska = try startReport("Alaska", children: 1, in: context)
        #expect(ReportStages.setStage(2, of: squishies[0], context: context))
        ReportStages.setPresentDay(AppCalendar.addingDays(3, to: Date()), for: squishies[0], context: context)
        parakeets[0].restingUntil = AppCalendar.addingDays(10, to: Date())
        #expect(ReportStages.setStage(4, of: alaska[0], context: context))
        #expect(CoreDataTestHelpers.save(context))

        let rows = squishies + fossils + parakeets + alaska
        let board = ReportBoard.make(from: rows, yearStart: .distantPast, context: context)

        #expect(board.presentingSoon.map { $0.anchor.title } == ["Squishies"])
        #expect(board.presentingSoon.first?.studentIDs.count == 2)
        #expect(board.stages.map(\.name) == ["Topic", "Writing"])
        #expect(board.stages.first?.reports.map { $0.anchor.title } == ["Fossils"])
        #expect(board.resting.map { $0.anchor.title } == ["Parakeets"])
        #expect(board.presented.map { $0.anchor.title } == ["Alaska"])
    }

    @Test("Report lessons are the ones named as reports or making report work")
    func reportLessonsAreNamedOrDefaultToReports() throws {
        let context = try CoreDataTestHelpers.makeContext()
        _ = CoreDataTestHelpers.seedLesson(in: context, name: "Research Report", area: "Language")
        _ = CoreDataTestHelpers.seedLesson(in: context, name: "Book Report: New", area: "Language")
        let biography = CoreDataTestHelpers.seedLesson(in: context, name: "Biography", area: "History")
        biography.defaultWorkKind = .report
        _ = CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game", area: "Math")
        #expect(CoreDataTestHelpers.save(context))

        let names = ReportStages.reportLessons(in: context).map(\.name)
        #expect(names == ["Biography", "Book Report: New", "Research Report"])
    }
}
