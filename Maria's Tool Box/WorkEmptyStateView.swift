import SwiftUI

struct WorkEmptyStateView: View {
    enum StateType {
        case noWork
        case noMatchingFilters
    }
    
    let type: StateType
    
    #if os(macOS)
    let platform: Platform = .macOS
    #else
    let platform: Platform = .iOS
    #endif
    
    enum Platform {
        case macOS, iOS
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: AppTheme.FontSize.titleMedium, weight: .semibold, design: .rounded))
            Text(subtitle)
                .font(.system(size: AppTheme.FontSize.body, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var title: String {
        switch type {
        case .noWork:
            return "No work yet"
        case .noMatchingFilters:
            return "No work matches your filters"
        }
    }
    
    private var subtitle: String {
        switch type {
        case .noWork:
            switch platform {
            case .macOS:
                return "Click the plus button to add work."
            case .iOS:
                return "Tap the plus to add work."
            }
        case .noMatchingFilters:
            switch platform {
            case .macOS:
                return "Try adjusting the filters on the left."
            case .iOS:
                return "Adjust filters from the toolbar."
            }
        }
    }
}
