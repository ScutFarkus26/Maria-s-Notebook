import SwiftUI
import CoreData

// MARK: - Field Label

struct FieldLabel: View {
    let text: String
    var spacing: CGFloat = 8
    
    var body: some View {
        Text(text)
            .font(.workflowFieldLabel)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Pill Button Group

struct PillButtonGroup<Item: Identifiable & CaseIterable, Selection: Equatable>: View where Item: Hashable {
    let items: [Item]
    let selection: Selection
    let color: (Item) -> Color
    let icon: (Item) -> String
    let label: (Item) -> String
    let isSelected: (Item) -> Bool
    let onSelect: (Item) -> Void
    
    var body: some View {
        ForEach(Array(items), id: \.self) { item in
            SelectablePillButton(
                item: item,
                isSelected: isSelected(item),
                color: color(item),
                icon: icon(item),
                label: label(item)
            ) {
                adaptiveWithAnimation(.workflowSelection) {
                    onSelect(item)
                }
            }
        }
    }
}

// MARK: - Labeled Field Section

struct LabeledFieldSection<Content: View>: View {
    let label: String
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content
    
    init(label: String, spacing: CGFloat = 8, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.spacing = spacing
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            FieldLabel(text: label)
            content()
        }
    }
}
