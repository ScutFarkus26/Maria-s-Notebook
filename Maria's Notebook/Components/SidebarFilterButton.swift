import SwiftUI

struct FilterButton: View {
    let icon: String
    let title: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    let trailingIcon: String?
    let trailingIconRotationDegrees: Double
    let trailingIconColor: AnyShapeStyle
    let trailingIconAction: (() -> Void)?
    
    let trailingBadgeText: String?
    let trailingBadgeColor: Color

    init(
        icon: String,
        title: String,
        color: Color,
        isSelected: Bool,
        action: @escaping () -> Void,
        trailingIcon: String? = nil,
        trailingIconRotationDegrees: Double = 0,
        trailingIconColor: AnyShapeStyle = AnyShapeStyle(.secondary),
        trailingIconAction: (() -> Void)? = nil,
        trailingBadgeText: String? = nil,
        trailingBadgeColor: Color = .secondary
    ) {
        self.icon = icon
        self.title = title
        self.color = color
        self.isSelected = isSelected
        self.action = action
        self.trailingIcon = trailingIcon
        self.trailingIconRotationDegrees = trailingIconRotationDegrees
        self.trailingIconColor = trailingIconColor
        self.trailingIconAction = trailingIconAction
        self.trailingBadgeText = trailingBadgeText
        self.trailingBadgeColor = trailingBadgeColor
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)

            Text(title)
                .font(AppTheme.ScaledFont.caption)
                .lineLimit(1)

            Spacer(minLength: 0)
            
            if let badge = trailingBadgeText {
                Text(badge)
                    .font(AppTheme.ScaledFont.captionSmallSemibold)
                    .foregroundStyle(trailingBadgeColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(trailingBadgeColor.opacity(UIConstants.OpacityConstants.accent)))
            }

            if let trailingIcon {
                if let trailingIconAction {
                    Button(action: trailingIconAction) {
                        Image(systemName: trailingIcon)
                            .foregroundStyle(trailingIconColor)
                            .rotationEffect(.degrees(trailingIconRotationDegrees))
                            .frame(width: 14, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: trailingIcon)
                        .foregroundStyle(trailingIconColor)
                        .rotationEffect(.degrees(trailingIconRotationDegrees))
                        .frame(width: 14, height: 28)
                        .contentShape(Rectangle())
                }
            }
        }
        .frame(height: 28, alignment: .leading)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(UIConstants.OpacityConstants.light) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

struct SidebarFilterButton: View {
    let icon: String
    let title: String
    let color: Color
    let isSelected: Bool
    let trailingIcon: String?
    let trailingIconRotationDegrees: Double
    let trailingIconColor: AnyShapeStyle
    let trailingIconAction: (() -> Void)?
    let trailingBadgeText: String?
    let trailingBadgeColor: Color
    let action: () -> Void

    init(
        icon: String,
        title: String,
        color: Color,
        isSelected: Bool,
        trailingIcon: String? = nil,
        trailingIconRotationDegrees: Double = 0,
        trailingIconColor: AnyShapeStyle = AnyShapeStyle(.secondary),
        trailingIconAction: (() -> Void)? = nil,
        trailingBadgeText: String? = nil,
        trailingBadgeColor: Color = .secondary,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.color = color
        self.isSelected = isSelected
        self.trailingIcon = trailingIcon
        self.trailingIconRotationDegrees = trailingIconRotationDegrees
        self.trailingIconColor = trailingIconColor
        self.trailingIconAction = trailingIconAction
        self.trailingBadgeText = trailingBadgeText
        self.trailingBadgeColor = trailingBadgeColor
        self.action = action
    }

    var body: some View {
        FilterButton(
            icon: icon,
            title: title,
            color: color,
            isSelected: isSelected,
            action: action,
            trailingIcon: trailingIcon,
            trailingIconRotationDegrees: trailingIconRotationDegrees,
            trailingIconColor: trailingIconColor,
            trailingIconAction: trailingIconAction,
            trailingBadgeText: trailingBadgeText,
            trailingBadgeColor: trailingBadgeColor
        )
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        SidebarFilterButton(
            icon: "folder.fill",
            title: "Example",
            color: .blue,
            isSelected: true,
            trailingIcon: "chevron.right",
            trailingIconRotationDegrees: 90,
            action: {}
        )
        SidebarFilterButton(
            icon: "doc.text",
            title: "Example 2",
            color: .pink,
            isSelected: false,
            action: {}
        )
    }
    .padding()
}
