import SwiftUI

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

// MARK: - Card Background Modifier

struct CardBackground: ViewModifier {
    let color: Color
    let cornerRadius: CGFloat
    
    init(color: Color = Color.primary.opacity(UIConstants.OpacityConstants.whisper), cornerRadius: CGFloat = 12) {
        self.color = color
        self.cornerRadius = cornerRadius
    }
    
    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(color)
        )
    }
}

extension View {
    func cardBackground(color: Color = Color.primary.opacity(UIConstants.OpacityConstants.whisper), cornerRadius: CGFloat = 12) -> some View {
        modifier(CardBackground(color: color, cornerRadius: cornerRadius))
    }
}

// MARK: - Animation Extensions

extension Animation {
    static let workflowToggle = Animation.easeInOut(duration: 0.15)
    static let workflowSelection = Animation.spring(response: 0.3, dampingFraction: 0.7)
}

// MARK: - Font Extensions

extension Font {
    static let workflowFieldLabel = Font.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded)
    static let workflowBody = Font.system(size: AppTheme.FontSize.body, weight: .bold, design: .rounded)
    static let workflowBodyMedium = Font.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded)
    static let workflowCaption = Font.system(size: AppTheme.FontSize.caption, design: .rounded)
    static let workflowCallout = Font.system(size: AppTheme.FontSize.callout, weight: .medium, design: .rounded)
}
