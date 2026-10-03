// TodayMarkPresented.swift
// A lesson row's "Mark Presented Now": recorded today for the children
// attendance says were there.
//
// It goes through `PresentationRecorder.record`, as the sheet's Record and the
// Ready row's Presented do, so a child marked absent today stays on the plan
// instead of being recorded. Until 2026-10-03 it recorded every child on the
// lesson, absent ones too, and began following each of them up. Nothing else
// is applied: no practice work, no observation.

import CoreData
import Foundation

enum TodayMarkPresented {

    static func record(
        _ assignment: CDLessonAssignment,
        now: Date = Date(),
        context: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator
    ) throws -> PresentationRecorder.Result {
        let day = AppCalendar.startOfDay(now)
        let planned = Set(assignment.resolvedStudentIDs)
        let absent = PresentationRecorder.absentStudentIDs(on: day, among: planned, context: context)
        return try PresentationRecorder.record(
            assignment,
            presentIDs: planned.subtracting(absent),
            on: day,
            context: context,
            saveCoordinator: saveCoordinator
        )
    }

    /// "Marked presented", plus who stays on the plan: "Theo S was absent and
    /// stays on the plan."
    static func message(keptOnPlan names: [String]) -> String {
        guard !names.isEmpty else { return "Marked presented" }
        let verb = names.count == 1 ? "was absent and stays" : "were absent and stay"
        return "Marked presented. \(PresentationSessionSummary.list(names)) \(verb) on the plan."
    }
}
