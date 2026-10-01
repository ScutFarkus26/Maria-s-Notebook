import SwiftUI
import CoreData

/// One scope above the roster, with the number of children it holds.
struct RosterScope: Identifiable, Equatable {
    let filter: StudentsFilter
    let count: Int

    var id: String { filter.storageValue }
}

/// Horizontal row of filter chips shown above the roster list.
/// Unlike a menu, the active scope is always visible, and every chip carries
/// a live count so attendance and lesson state read at a glance.
struct StudentsScopeChips: View {
    let scopes: [RosterScope]
    let selectedFilter: StudentsFilter
    let onSelect: (StudentsFilter) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(scopes) { scope in
                    chip(for: scope)
                }
            }
        }
    }

    private func chip(for scope: RosterScope) -> some View {
        let isSelected = selectedFilter == scope.filter
        return Button {
            adaptiveWithAnimation { onSelect(scope.filter) }
        } label: {
            HStack(spacing: 4) {
                Text(scope.filter.chipTitle)
                Text("\(scope.count)")
                    .opacity(0.7)
            }
            .font(AppTheme.ScaledFont.captionSemibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .capsuleFill(
                isSelected
                    ? Color.accentColor.opacity(UIConstants.OpacityConstants.accent)
                    : Color.secondary.opacity(UIConstants.OpacityConstants.light)
            )
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(scope.filter.title), \(scope.count) students")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
