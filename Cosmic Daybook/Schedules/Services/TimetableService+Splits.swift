// TimetableService+Splits.swift
// Which blocks a This Day and After split made: the copy it starts takes an id
// worked out from the block it was split from and its first day, so a later
// delete can end the copies too, and only those.

import CoreData
import CryptoKit
import Foundation

extension TimetableService {

    /// The id a This Day and After split gives the copy of `blockID` that
    /// starts on `validFrom`: the first 16 bytes of a SHA-256 of the two,
    /// marked as an RFC 9562 version 8 (custom) UUID. The same block and day
    /// give the same id on every device. The day goes in as whole seconds
    /// since 2001, which iCloud keeps exactly, so no time zone changes it.
    nonisolated static func splitCopyID(of blockID: UUID, from validFrom: Date) -> UUID {
        let seconds = Int64(validFrom.timeIntervalSinceReferenceDate.rounded())
        let seed = "TimetableBlockSplit|\(blockID.uuidString)|\(seconds)"
        var bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// `block` and every block split from it or that it was split from, all
    /// the way along, in either direction: the one weekly block as Danny sees
    /// it, however many This Day and After edits cut it into pieces.
    ///
    /// Only a split's own copy counts (its id is `splitCopyID` of the block
    /// it came from). `replaceWeek` (MCP's set_timetable) and `copyDay` also
    /// start blocks in the same lane and on the same weekday where others
    /// end, and those are other blocks: a delete must never end them. A split
    /// made before 2026-11-06 gave its copy a random id, so it isn't found.
    static func splitFamily(of block: CDTimetableBlock, in context: NSManagedObjectContext) -> [CDTimetableBlock] {
        guard !block.isOneOff, block.id != nil, let weekdayRaw = block.weekdayRaw else { return [block] }
        let request = CDFetchRequest(CDTimetableBlock.self)
        request.predicate = NSPredicate(
            format: "laneID ==[c] %@ AND weekdayRaw == %@ AND onDay == nil", block.laneID, weekdayRaw
        )
        let siblings = context.safeFetch(request).filter { !$0.isDeleted && $0.id != nil }
        guard siblings.count > 1 else { return [block] }

        /// Whether `child` is the copy a split of `parent` made.
        func isCopy(_ child: CDTimetableBlock, of parent: CDTimetableBlock) -> Bool {
            guard let childID = child.id, let parentID = parent.id, let from = child.validFrom else { return false }
            return childID == splitCopyID(of: parentID, from: from)
        }
        var family: [CDTimetableBlock] = [block]
        var seen: Set<NSManagedObjectID> = [block.objectID]
        var next = 0
        while next < family.count {
            let member = family[next]
            next += 1
            for other in siblings where !seen.contains(other.objectID)
                && (isCopy(other, of: member) || isCopy(member, of: other)) {
                seen.insert(other.objectID)
                family.append(other)
            }
        }
        return family
    }
}
