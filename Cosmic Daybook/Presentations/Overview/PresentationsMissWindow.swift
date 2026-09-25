import Foundation

enum PresentationsMissWindow: String, CaseIterable, Sendable {
    case all
    case d1
    case d2
    case d3

    var threshold: Int? {
        switch self {
        case .all: return nil
        case .d1: return 1
        case .d2: return 2
        case .d3: return 3
        }
    }
}
