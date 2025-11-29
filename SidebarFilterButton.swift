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

    init(
        icon: String,
        title: String,
        color: Color,
        isSelected: Bool,
        action: @escaping () -> Void,
        trailingIcon: String? = nil,
        trailingIconRotationDegrees: Double = 0,
        trailingIconColor: AnyShapeStyle = AnyShapeStyle(.secondary),
        trailingIconAction: (() -> Void)? = nil
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
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)

            Text(title)
                .font(.system(size: AppTheme.FontSize.caption))
                .lineLimit(1)

            Spacer(minLength: 0)

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
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
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
            trailingIconAction: trailingIconAction
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

