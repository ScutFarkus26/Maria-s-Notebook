//
//  MCPNotebookTools+WorkCheckIns.swift
//  Maria's Notebook
//
//  Completing and moving a scheduled check-in, for update_work.
//
//  A check-in is named by its day — there is no id for one over MCP — so
//  `move_check_in_from` finds it the same way `complete_check_in_on` does:
//  one lookup, shared between the two, so the two arguments can never
//  disagree about which check-in a date means.
//
//  Work assigned to several children is one row per child, each with its own
//  check-in row for the same day, all written together by assign_work. A
//  reschedule is that one decision reconsidered, so the linked copies move
//  together by default. A copy whose check-in was already completed keeps its
//  day — the guide saw that child — and the receipt names it, so the group
//  never ends up split across two days without the reply saying so.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Lookup

    /// Every check-in on `day`, through the relationship and the `workID`
    /// string both.
    static func checkIns(
        of work: CDWorkModel, on day: Date, in modelContext: NSManagedObjectContext
    ) -> [CDWorkCheckIn] {
        checkIns(of: work, in: modelContext).filter { checkIn in
            guard let date = checkIn.date else { return false }
            return AppCalendar.isSameDay(date, day)
        }
    }

    /// The check-in still scheduled on `day`. One that is already completed
    /// or skipped is refused by its status; a day with none at all lists the
    /// days that do have one, so the caller can correct the date without
    /// another read.
    static func scheduledCheckIn(
        of work: CDWorkModel, on day: Date, in modelContext: NSManagedObjectContext
    ) throws -> CDWorkCheckIn {
        let onDay = checkIns(of: work, on: day, in: modelContext)
        if let scheduled = onDay.first(where: { $0.status == .scheduled }) {
            return scheduled
        }
        if let settled = onDay.first {
            throw MCPToolError(
                "The check-in on \(dayString(day)) is already \(settled.status.rawValue.lowercased())."
            )
        }
        let days = Set(checkIns(of: work, in: modelContext).compactMap(\.date).map(AppCalendar.startOfDay))
            .sorted().map(dayString)
        let hint = days.isEmpty
            ? "It has no check-ins."
            : "Its check-ins are on \(days.joined(separator: ", "))."
        throw MCPToolError("No check-in is scheduled on \(dayString(day)) for this work. \(hint)")
    }

    // MARK: - Completing

    static func applyCheckInCompletion(
        _ arguments: [String: JSONValue], to work: CDWorkModel,
        in modelContext: NSManagedObjectContext
    ) throws -> [String] {
        guard let day = try dayArgument(arguments, "complete_check_in_on") else { return [] }
        let checkIn = try scheduledCheckIn(of: work, on: day, in: modelContext)
        checkIn.status = .completed
        return ["completed the check-in on \(dayString(day))"]
    }

    // MARK: - Moving

    /// `move_check_in_from` / `move_check_in_to`, required together. Returns
    /// one receipt line for this row and one for each linked copy, so a caller
    /// can see every row the move touched — or deliberately left alone.
    static func applyCheckInMove(
        _ arguments: [String: JSONValue], to work: CDWorkModel,
        in modelContext: NSManagedObjectContext
    ) throws -> [String] {
        let fromDay = try dayArgument(arguments, "move_check_in_from").map(AppCalendar.startOfDay)
        let toDay = try dayArgument(arguments, "move_check_in_to").map(AppCalendar.startOfDay)
        guard fromDay != nil || toDay != nil else { return [] }
        guard let fromDay else {
            throw MCPToolError("move_check_in_to needs move_check_in_from — the day of the check-in to move.")
        }
        guard let toDay else {
            throw MCPToolError("move_check_in_from needs move_check_in_to — the day it moves to.")
        }

        // Everything that can refuse happens before anything is written, so a
        // refusal never leaves a half-moved group behind.
        let checkIn = try scheduledCheckIn(of: work, on: fromDay, in: modelContext)
        // Same rule as update_year_plan_entry: a closed day lands on the next
        // open one, and the receipt says so rather than letting it pass.
        let landing = YearPlanPacing.schoolDay(onOrAfter: toDay, in: modelContext)
        let from = dayString(fromDay)
        let to = dayString(landing)
        let detour = landing == toDay
            ? ""
            : " (\(dayString(toDay)) is not a school day, so it moved forward to \(to))"
        guard landing != fromDay else {
            let why = landing == toDay
                ? "."
                : " — \(dayString(toDay)) is not a school day, and \(to) is the next open one."
            throw MCPToolError("The check-in is already on \(from)\(why)")
        }

        move(checkIn, toDay: landing)
        var changes = ["moved the check-in from \(from) to \(to)\(detour)"]

        let siblings = WorkGrouping.group(containing: work, in: modelContext).siblings
        guard !siblings.isEmpty else { return changes }
        if arguments["move_check_in_for_this_child_only"]?.boolValue == true {
            let count = siblings.count
            changes.append(
                "this child only — \(count) linked "
                    + (count == 1 ? "copy still has its" : "copies still have their")
                    + " check-in on \(from)"
            )
            return changes
        }
        for sibling in siblings {
            changes.append(moveSiblingCheckIn(of: sibling, from: fromDay, to: landing, in: modelContext))
        }
        return changes
    }

    /// One linked copy's line of the receipt: moved, kept because its
    /// check-in was already completed or skipped, or had nothing on that day.
    private static func moveSiblingCheckIn(
        of sibling: CDWorkModel, from fromDay: Date, to landing: Date,
        in modelContext: NSManagedObjectContext
    ) -> String {
        let owner = WorkGrouping.owner(of: sibling).map { "\(studentNames(for: [$0], in: modelContext))'s" }
        let label = "\(owner ?? "an unowned") linked copy [work id=\(sibling.id?.uuidString ?? "unknown")]"
        let onDay = checkIns(of: sibling, on: fromDay, in: modelContext)
        if let scheduled = onDay.first(where: { $0.status == .scheduled }) {
            move(scheduled, toDay: landing)
            return "also moved \(label)"
        }
        if let settled = onDay.first {
            return "\(label) stayed on \(dayString(fromDay)) — its check-in is already "
                + settled.status.rawValue.lowercased()
        }
        return "\(label) has no check-in on \(dayString(fromDay))"
    }

    /// Only the day changes. The time of day is kept, as the Today view's
    /// "bump to tomorrow" keeps it, so the row's place in the day's ordering
    /// stays where it was; purpose, status and notes are not touched.
    private static func move(_ checkIn: CDWorkCheckIn, toDay day: Date) {
        let calendar = AppCalendar.shared
        let time = calendar.dateComponents([.hour, .minute, .second], from: checkIn.date ?? day)
        checkIn.date = calendar.date(
            bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: day
        ) ?? day
    }
}
