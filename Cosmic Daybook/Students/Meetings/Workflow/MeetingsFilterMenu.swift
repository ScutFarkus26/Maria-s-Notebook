import SwiftUI

/// The Meetings toolbar's one menu: which level shows, how often each child
/// meets, which ages show, and how Up Next is ordered.
struct MeetingsFilterMenu: View {
    @Binding var cadenceDays: Int
    /// The chosen level; nil shows every level.
    @Binding var level: CDStudent.Level?
    /// The levels the enrolled children are in. With only one, the menu
    /// offers no Level choice.
    var levels: [CDStudent.Level]
    @Binding var selectedAgeRanges: Set<AgeRange>
    @Binding var orderRaw: String
    var iconOnly = false

    static let cadenceChoices = [3, 5, 7, 10, 14, 21, 30]

    private var order: MeetingQueueOrder { MeetingQueueOrder(rawValue: orderRaw) ?? .need }

    var body: some View {
        Menu {
            // First: the choice that changes most, in reach without scrolling the menu on a phone.
            if levels.count > 1 {
                Section("Level") {
                    checkButton("All Levels", checked: level == nil) { level = nil }
                    ForEach(levels, id: \.self) { choice in
                        checkButton(choice.title, checked: level == choice) { level = choice }
                    }
                }
            }
            Section("Meet Every") {
                ForEach(Self.cadenceChoices, id: \.self) { days in
                    checkButton("\(days) days", checked: cadenceDays == days) { cadenceDays = days }
                }
            }
            Section("Ages") {
                checkButton("All Ages", checked: selectedAgeRanges.isEmpty) { selectedAgeRanges = [] }
                ForEach(AgeRange.allCases) { range in
                    checkButton(range.rawValue, checked: selectedAgeRanges.contains(range)) {
                        if selectedAgeRanges.contains(range) {
                            selectedAgeRanges.remove(range)
                        } else {
                            selectedAgeRanges.insert(range)
                        }
                    }
                }
            }
            Section("Order") {
                ForEach(MeetingQueueOrder.allCases, id: \.self) { choice in
                    checkButton(choice.label, checked: order == choice) { orderRaw = choice.rawValue }
                }
            }
        } label: {
            if iconOnly {
                Label(summary, systemImage: "line.3.horizontal.decrease.circle")
                    .labelStyle(.iconOnly)
            } else {
                Label(summary, systemImage: "line.3.horizontal.decrease.circle")
                    .labelStyle(.titleAndIcon)
            }
        }
        .help("Level, cadence, ages and order")
    }

    // Checkmarked buttons, not an inline Picker: a String-tagged Picker inside
    // a toolbar Menu crashed the iPhone (the roster's sort menu, 2026-10-01).
    private func checkButton(_ title: String, checked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if checked {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private var summary: String {
        let ages: String
        switch selectedAgeRanges.count {
        case 0: ages = "All ages"
        case 1: ages = selectedAgeRanges.first?.rawValue ?? "1 age"
        default: ages = "\(selectedAgeRanges.count) ages"
        }
        // A chosen level stands in for "All ages".
        guard let level else { return "Every \(cadenceDays) days · \(ages)" }
        let parts = ["Every \(cadenceDays) days", level.title] + (selectedAgeRanges.isEmpty ? [] : [ages])
        return parts.joined(separator: " · ")
    }
}
