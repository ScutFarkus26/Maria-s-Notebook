import SwiftUI

extension WorkModel.WorkType {
    var title: String { self.rawValue }
    var color: Color {
        switch self {
        case .research: return .teal
        case .followUp: return .orange
        case .practice: return .purple
        }
    }
}
