// SchedulesPageModel+Editing.swift
// The Schedules page's edits. Each goes through `TimetableService`, which
// changes objects without saving, then saves on the view context (so
// `SharedStoreOrphanGuard` shares new rows) and reads the page again. A
// failed save raises the app's plain save alert.

import CoreData
import Foundation

extension SchedulesPageModel {

    // MARK: - Editing

    /// Makes the starter lanes: our class, the adolescent room and the guide's own.
    @discardableResult
    func setUp() -> Bool {
        TimetableService.makeStarterLanes(in: context, now: now())
        return save("Set up schedules")
    }

    @discardableResult
    func addPerson(named name: String) -> Bool {
        let name = name.trimmed()
        guard !name.isEmpty else { return false }
        TimetableService.addPerson(named: name, in: context, now: now())
        return save("Add a person's lane")
    }

    /// The lanes as the Lanes sheet holds them, in their order.
    var laneEdits: [LaneEdit] {
        lanes.map { LaneEdit(id: $0.id, name: $0.name, colorRaw: $0.colorRaw, kind: $0.kind, isGuide: $0.isGuide) }
    }

    /// Renames, recolors and reorders the lanes as `edits` has them. An empty
    /// name keeps the old one.
    @discardableResult
    func applyLaneEdits(_ edits: [LaneEdit]) -> Bool {
        let stored = Dictionary(
            TimetableService.lanes(in: context).compactMap { lane in lane.id.map { ($0, lane) } },
            uniquingKeysWith: { first, _ in first }
        )
        let at = now()
        var ordered: [CDTimetableLane] = []
        for edit in edits {
            guard let lane = stored[edit.id] else { continue }
            if !edit.name.trimmed().isEmpty { TimetableService.rename(lane, to: edit.name, now: at) }
            TimetableService.setColor(edit.colorRaw, of: lane, now: at)
            ordered.append(lane)
        }
        // Any lane the sheet didn't list keeps its place after the others.
        ordered += stored.values.filter { lane in !ordered.contains(lane) }
            .sorted { $0.sortOrder < $1.sortOrder }
        TimetableService.reorder(ordered, now: at)
        return save("Edit lanes")
    }

    /// Adds a weekly block on each of `weekdays`, from the start of the week shown.
    @discardableResult
    func addBlock(_ values: TimetableBlockValues, laneID: UUID, on weekdays: [Weekday]) -> Bool {
        guard let lane = storedLane(laneID), !weekdays.isEmpty else { return false }
        let from = Self.weekDays(containing: day, calendar: calendar).first ?? day
        TimetableService.addBlock(
            values, to: lane, on: weekdays, from: from, in: context, now: now(), calendar: calendar
        )
        return save("Add a schedule block")
    }

    /// Add to This Day: a one-off on `day`.
    @discardableResult
    func addOneOff(_ values: TimetableBlockValues, laneID: UUID, on day: Date) -> Bool {
        guard let lane = storedLane(laneID) else { return false }
        TimetableService.addOneOff(values, to: lane, on: day, in: context, now: now(), calendar: calendar)
        return save("Add to this day")
    }

    @discardableResult
    func edit(
        blockID: UUID, to values: TimetableBlockValues, scope: TimetableService.EditScope, on day: Date
    ) -> Bool {
        guard let block = storedBlock(blockID) else { return false }
        TimetableService.edit(block, to: values, scope: scope, on: day, in: context, now: now(), calendar: calendar)
        return save("Edit a schedule block")
    }

    @discardableResult
    func delete(blockID: UUID, scope: TimetableService.EditScope, on day: Date) -> Bool {
        guard let block = storedBlock(blockID) else { return false }
        TimetableService.delete(block, scope: scope, on: day, in: context, now: now(), calendar: calendar)
        return save("Delete a schedule block")
    }

    /// Cancels a weekly block on `day` only.
    @discardableResult
    func cancel(blockID: UUID, on day: Date) -> Bool {
        guard let block = storedBlock(blockID) else { return false }
        TimetableService.cancel(block, on: day, in: context, now: now(), calendar: calendar)
        return save("Cancel a block for a day")
    }

    /// Takes away a block's change on `day`: it reads as every week again.
    @discardableResult
    func undoChange(blockID: UUID, on day: Date) -> Bool {
        guard let block = storedBlock(blockID) else { return false }
        TimetableService.undoChanges(to: block, on: day, in: context, calendar: calendar)
        return save("Undo a day's change")
    }

    /// Takes away every change on `day`, people out included.
    @discardableResult
    func undoAllChanges(on day: Date) -> Bool {
        TimetableService.undoAllChanges(on: day, in: context, calendar: calendar)
        return save("Undo a day's changes")
    }

    /// Out Today on a person lane, or back in.
    @discardableResult
    func setOut(laneID: UUID, _ isOut: Bool, on day: Date) -> Bool {
        guard let lane = storedLane(laneID) else { return false }
        TimetableService.setOut(lane, isOut, on: day, in: context, now: now(), calendar: calendar)
        return save(isOut ? "Out today" : "Back in")
    }

    /// Copy Day To…: `laneID`'s weekly blocks on `source` onto each of `targets`.
    @discardableResult
    func copyDay(_ source: Weekday, laneID: UUID, to targets: [Weekday]) -> Bool {
        guard let lane = storedLane(laneID), !targets.isEmpty else { return false }
        TimetableService.copyDay(source, of: lane, to: targets, in: context, now: now(), calendar: calendar)
        return save("Copy a day")
    }

    /// Whether the block is a weekly one, which asks Only This Day or This Day and After.
    func isRepeating(blockID: UUID) -> Bool {
        storedBlock(blockID).map { !$0.isOneOff } ?? false
    }

    // MARK: - Steps

    func storedLane(_ id: UUID) -> CDTimetableLane? {
        TimetableService.lanes(in: context).first { $0.id == id }
    }

    func storedBlock(_ id: UUID) -> CDTimetableBlock? {
        let request = CDFetchRequest(CDTimetableBlock.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return context.safeFetch(request).first { !$0.isDeleted }
    }

    /// Saves on the view context (the coordinator's alert says so if it
    /// fails), then reads the page again either way.
    func save(_ reason: String) -> Bool {
        let saved = saveCoordinator.save(context, reason: reason)
        reload()
        return saved
    }
}
