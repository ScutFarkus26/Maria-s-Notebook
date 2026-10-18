import Foundation
import CoreData

nonisolated extension CDBookClubSession {
    /// True if this club's run (start to end; still running when it has no
    /// end and isn't finished) overlaps `range`. A club with no dates fails open.
    func overlaps(_ range: DateRange) -> Bool {
        guard let start = startDate ?? createdAt else { return true }
        if start >= range.end { return false }
        if let endDate { return endDate >= range.start }
        switch status {
        case .active, .planned: return true
        case .completed, .archived: return (modifiedAt ?? start) >= range.start
        }
    }
}
