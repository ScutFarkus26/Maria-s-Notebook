import SwiftUI
import CoreData

/// Horizontal row of filter chips shown above the roster list.
/// Unlike a menu, the active scope is always visible, and the All/Here chips
/// carry live counts so attendance state is readable at a glance.
struct StudentsScopeChips: View {
    let selectedFilter: StudentsFilter
    let allCount: Int
    let hereCount: Int
    let onSelect: (StudentsFilter) -> Void

    private let filters: [StudentsFilter] = [.all, .presentNow, .upper, .lower, .adolescent]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(filters, id: \.self) { filter in
                    chip(for: filter)
                }
            }
        }
    }

    private func count(for filter: StudentsFilter) -> Int? {
        switch filter {
        case .all: return allCount
        case .presentNow: return hereCount
        default: return nil
        }
    }

    private func chip(for filter: StudentsFilter) -> some View {
        let isSelected = selectedFilter == filter
        return Button {
            adaptiveWithAnimation { onSelect(filter) }
        } label: {
            HStack(spacing: 4) {
                Text(filter.chipTitle)
                if let count = count(for: filter) {
                    Text("\(count)")
                        .opacity(0.7)
                }
            }
            .font(AppTheme.ScaledFont.captionSemibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(
                    isSelected
                        ? Color.accentColor.opacity(UIConstants.OpacityConstants.accent)
                        : Color.secondary.opacity(UIConstants.OpacityConstants.light)
                )
            )
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: filter))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func accessibilityLabel(for filter: StudentsFilter) -> String {
        if let count = count(for: filter) {
            return "\(filter.title), \(count) students"
        }
        return filter.title
    }
}
