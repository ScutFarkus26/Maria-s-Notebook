import SwiftUI
import CoreData

// MARK: - CDWorkModel Check-in Counts

struct CheckInCounts {
    let completed: Int
    let total: Int
    let upcoming: Int
}

extension CDWorkModel {
    func checkInCounts() -> CheckInCounts {
        let list = (participants?.allObjects as? [CDWorkParticipantEntity]) ?? []
        let total = list.count
        let completed = list.reduce(0) { partial, p in
            partial + (p.completedAt != nil ? 1 : 0)
        }
        let upcoming = max(0, total - completed)
        return CheckInCounts(completed: completed, total: total, upcoming: upcoming)
    }
}
