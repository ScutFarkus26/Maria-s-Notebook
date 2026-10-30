// ReportStages.swift
// A child's report and where it stands (2026-10-30).
//
// A report goes Topic, Research, Writing, Ready, Presented. The stages are
// the report's steps: the one she's at is the first step not yet ticked, and
// the steps before it carry the day each was passed. A report that already
// has steps of its own keeps them as its stages. Presented is the work's
// status, not a tick: a report closed as Finished (or Mastered) has been
// presented, so a close and its undo through `WorkLogService` move the stage
// with it.
//
// Children who write a report together have linked copies, one each, and
// they're one report: a stage set on one copy is set on every copy still
// open or presented. A copy closed another way (a child who dropped the
// report) is left as it is.
//
// The day she presents to the class is a check-in with its own purpose, so
// it shows on Today and the Scheduled strip like any other check-in.
// Plan: docs/Plans/Plan - Reports and to-dos in meetings.md

import CoreData
import Foundation

enum ReportStages {

    /// The five stages a report goes through when it has no steps of its own.
    static let standardTitles = ["Topic", "Research", "Writing", "Ready", "Presented"]

    /// The purpose of the check-in on the day she presents to the class.
    static let presentPurpose = "Present to the class"

    static func isReport(_ work: CDWorkModel) -> Bool {
        work.kind == .report
    }

    // MARK: - Reading

    /// The report's stages: its own steps, or the five when it has none yet.
    static func titles(of work: CDWorkModel) -> [String] {
        let steps = work.orderedSteps
        return steps.isEmpty ? standardTitles : steps.map(\.title)
    }

    /// Closed as Finished or Mastered: she has presented it.
    static func hasBeenPresented(_ work: CDWorkModel) -> Bool {
        work.status == .done || work.status == .mastered
    }

    /// The stage she's at, as an index into `titles(of:)`: the first step not
    /// yet ticked. Nil once the report has been presented. An open report
    /// with every step ticked is at its last stage.
    static func currentStage(of work: CDWorkModel) -> Int? {
        if hasBeenPresented(work) { return nil }
        let steps = work.orderedSteps
        guard !steps.isEmpty else { return 0 }
        return steps.firstIndex { !$0.isCompleted } ?? steps.count - 1
    }

    /// "Writing", "Presented", or nil for a report closed another way.
    static func stageName(of work: CDWorkModel) -> String? {
        let titles = titles(of: work)
        if hasBeenPresented(work) { return titles.last }
        guard work.status.isOpen, let current = currentStage(of: work) else { return nil }
        return titles[min(current, titles.count - 1)]
    }

    /// The copies a stage moves: `work` and every linked copy still open or
    /// presented.
    static func movingCopies(of work: CDWorkModel, in context: NSManagedObjectContext) -> [CDWorkModel] {
        WorkGrouping.group(containing: work, in: context).members.filter {
            $0 === work || $0.status.isOpen || hasBeenPresented($0)
        }
    }

    // MARK: - Setting a stage

    /// Puts each copy at `stage`, in memory: the five steps are added where
    /// there are none, the stages before it are ticked (a stage passed
    /// earlier keeps its day) and it and the later ones are unticked.
    /// Returns the status changes to log: the last stage closes the open
    /// copies as Finished, and an earlier one reopens copies presented
    /// before. Doesn't save.
    static func set(
        stage: Int, on copies: [CDWorkModel], day: Date = Date(), context: NSManagedObjectContext
    ) -> [WorkLogService.Entry] {
        let passedOn = AppCalendar.startOfDay(day)
        var entries: [WorkLogService.Entry] = []
        for copy in copies {
            addStandardSteps(to: copy, context: context)
            let steps = copy.orderedSteps
            guard !steps.isEmpty else { continue }
            let target = min(max(stage, 0), steps.count - 1)
            let isLast = target == steps.count - 1
            for (index, step) in steps.enumerated() {
                if index < target {
                    if step.completedAt == nil { step.completedAt = passedOn }
                } else if !isLast || index > target {
                    step.completedAt = nil
                }
            }
            if isLast {
                if copy.status.isOpen { entries.append(.init(work: copy, status: .done)) }
            } else if hasBeenPresented(copy) {
                entries.append(.init(work: copy, status: .active))
            }
        }
        return entries
    }

    /// Sets the stage outside a meeting (the Reports view): every moving
    /// copy, its status through `WorkLogService`, any rest ended, one save.
    /// Returns false, with nothing changed, when it didn't save.
    @discardableResult
    static func setStage(
        _ stage: Int, of work: CDWorkModel, context: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator? = nil
    ) -> Bool {
        let transaction = ContextMutationTransaction(context: context)
        let copies = movingCopies(of: work, in: context)
        let entries = set(stage: stage, on: copies, context: context)
        for copy in copies where copy.restingUntil != nil {
            copy.restingUntil = nil
        }
        do {
            if !entries.isEmpty {
                try WorkLogService.log(entries, context: context, saveImmediately: false)
            }
        } catch {
            transaction.rollback()
            return false
        }
        let saved = saveCoordinator?.save(context, reason: "Set report stage", alertOnFailure: false)
            ?? context.safeSave()
        guard saved else {
            transaction.rollback()
            return false
        }
        transaction.commit()
        return true
    }

    /// Gives a report with no steps the five stages, at Topic.
    static func addStandardSteps(to work: CDWorkModel, context: NSManagedObjectContext) {
        guard work.orderedSteps.isEmpty else { return }
        let service = WorkStepService(context: context)
        for title in standardTitles {
            _ = try? service.createStep(for: work, title: title)
        }
    }

    // MARK: - The day she presents

    /// Whether this check-in is the day she presents to the class.
    static func isPresentDay(_ checkIn: CDWorkCheckIn) -> Bool {
        checkIn.purpose.trimmed().caseInsensitiveCompare(presentPurpose) == .orderedSame
    }

    /// The day she's down to present, if one is set and hasn't happened.
    static func presentDay(of work: CDWorkModel) -> Date? {
        scheduledPresentDays(of: work).first?.date
    }

    /// Sets or clears the day she presents, on every moving copy: a day
    /// already set moves, or one is made; clearing skips it. Doesn't save.
    static func setPresentDay(_ day: Date?, for work: CDWorkModel, context: NSManagedObjectContext) {
        for copy in movingCopies(of: work, in: context) where copy.status.isOpen {
            let scheduled = scheduledPresentDays(of: copy)
            guard let day else {
                scheduled.forEach { $0.status = .skipped }
                continue
            }
            let landing = AppCalendar.startOfDay(day)
            if let first = scheduled.first {
                first.date = landing
                scheduled.dropFirst().forEach { $0.status = .skipped }
            } else {
                CDWorkCheckIn.make(for: copy, on: landing, purpose: presentPurpose, in: context)
            }
        }
    }

    /// `setPresentDay` and a save. Returns false, with nothing changed, when
    /// it didn't save.
    @discardableResult
    static func savePresentDay(_ day: Date?, for work: CDWorkModel, context: NSManagedObjectContext) -> Bool {
        let transaction = ContextMutationTransaction(context: context)
        setPresentDay(day, for: work, context: context)
        guard context.safeSave() else {
            transaction.rollback()
            return false
        }
        transaction.commit()
        return true
    }

    private static func scheduledPresentDays(of work: CDWorkModel) -> [CDWorkCheckIn] {
        let checkIns = (work.checkIns?.allObjects as? [CDWorkCheckIn]) ?? []
        return checkIns
            .filter { !$0.isDeleted && $0.status == .scheduled && isPresentDay($0) }
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }
}
