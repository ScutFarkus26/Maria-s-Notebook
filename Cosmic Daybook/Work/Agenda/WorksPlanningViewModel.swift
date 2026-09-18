import Foundation
import OSLog
import CoreData
import Observation

enum ActiveSheet: Identifiable, Equatable {
    case schedule(workID: UUID)
    case detail(workID: UUID)
    var id: String {
        switch self {
        case .schedule(let id): return "schedule-\(id)"
        case .detail(let id): return "detail-\(id)"
        }
    }
}
