// CalendarForwardShiftService+OnPlan.swift
// Which open work checks are still the plan's: the one set Move All Forward,
// Clear All, their counts, the strip's pills and its earliest day all read.
//
// Split from CalendarForwardShiftService.swift for SwiftLint's file-length
// limit.

import CoreData
import Foundation

extension CalendarForwardShiftService {

    /// The checks among `checkIns` that are still part of the plan: on open
    /// work whose child is still in the class. A departed child's copy stays
    /// where it is when her group moves (`WorkCheckInService.ownerHasLeft`),
    /// and the strip doesn't show her checks or closed work's (2026-10-14
    /// review), so Move All Forward, Clear All, their counts and the strip's
    /// earliest day all read this one set. A child who can't be found is
    /// treated as still here, as `ownerHasLeft` does. One student fetch for
    /// the lot.
    static func onPlan(_ checkIns: [CDWorkCheckIn], in context: NSManagedObjectContext) -> [CDWorkCheckIn] {
        let open = checkIns.compactMap { checkIn -> (checkIn: CDWorkCheckIn, work: CDWorkModel)? in
            guard !checkIn.isDeleted, let work = checkIn.resolvedWork(in: context), !work.isClosed else {
                return nil
            }
            return (checkIn, work)
        }
        let left = ownersWhoHaveLeft(Set(open.compactMap { WorkGrouping.owner(of: $0.work) }), in: context)
        guard !left.isEmpty else { return open.map(\.checkIn) }
        return open.filter { WorkGrouping.owner(of: $0.work).map { !left.contains($0) } ?? true }.map(\.checkIn)
    }

    /// Of `owners`, the children on file who are no longer enrolled. A
    /// duplicate row that is still enrolled counts her as here.
    private static func ownersWhoHaveLeft(_ owners: Set<UUID>, in context: NSManagedObjectContext) -> Set<UUID> {
        guard !owners.isEmpty else { return [] }
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = NSPredicate(format: "id IN %@", owners as NSSet)
        var left = Set<UUID>()
        var here = Set<UUID>()
        for student in context.safeFetch(request) {
            guard let id = student.id else { continue }
            if student.isEnrolled { here.insert(id) } else { left.insert(id) }
        }
        return left.subtracting(here)
    }

    /// The day of the soonest check still the plan's: the strip's earliest
    /// day. A stale check left scheduled on closed work, or a departed
    /// child's, used to hold the strip back to its day.
    static func firstScheduledCheckInDate(in context: NSManagedObjectContext) -> Date? {
        movableCheckIns(in: context).compactMap(\.date).min()
    }
}
