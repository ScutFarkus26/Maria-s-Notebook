import SwiftUI
import CoreData

// MARK: - Age Filter Picker

struct AgeFilterPicker: View {
    @Binding var selectedAgeRanges: Set<AgeRange>

    private static let summary = FilterSelectionSummary(allLabel: "All Ages")

    private var displayText: String {
        Self.summary.text(
            for: selectedAgeRanges,
            items: AgeRange.allCases,
            id: { $0 },
            label: { $0.rawValue }
        )
    }

    var body: some View {
        MultiSelectFilterMenu(
            items: AgeRange.allCases,
            selection: $selectedAgeRanges,
            id: { $0 },
            label: { $0.rawValue },
            allLabel: Self.summary.allLabel,
            menuLabel: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.caption)

                    Text(displayText)
                        .font(.subheadline.weight(.medium))

                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .capsuleFill(
                    selectedAgeRanges.isEmpty
                        ? Color.primary.opacity(UIConstants.OpacityConstants.veryFaint)
                        : Color.accentColor.opacity(UIConstants.OpacityConstants.medium)
                )
                .foregroundStyle(selectedAgeRanges.isEmpty ? Color.secondary : Color.accentColor)
            }
        )
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
    }
}
