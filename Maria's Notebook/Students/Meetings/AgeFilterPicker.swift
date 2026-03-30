import SwiftUI

// MARK: - Age Filter Picker

struct AgeFilterPicker: View {
    @Binding var selectedAgeRanges: Set<AgeRange>

    private var displayText: String {
        if selectedAgeRanges.isEmpty {
            return "All Ages"
        } else if selectedAgeRanges.count == 1, let first = selectedAgeRanges.first {
            return first.rawValue
        } else {
            return "\(selectedAgeRanges.count) Ages"
        }
    }

    var body: some View {
        Menu {
            Button("All Ages") {
                selectedAgeRanges.removeAll()
            }

            Divider()

            ForEach(AgeRange.allCases) { range in
                Button(action: {
                    if selectedAgeRanges.contains(range) {
                        selectedAgeRanges.remove(range)
                    } else {
                        selectedAgeRanges.insert(range)
                    }
                }, label: {
                    HStack {
                        if selectedAgeRanges.contains(range) {
                            Image(systemName: "checkmark")
                        }
                        Text(range.rawValue)
                    }
                })
            }
        } label: {
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
            .background(
                Capsule()
                    .fill(selectedAgeRanges.isEmpty ? Color.primary.opacity(UIConstants.OpacityConstants.veryFaint) : Color.accentColor.opacity(UIConstants.OpacityConstants.medium))
            )
            .foregroundStyle(selectedAgeRanges.isEmpty ? Color.secondary : Color.accentColor)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
    }
}
