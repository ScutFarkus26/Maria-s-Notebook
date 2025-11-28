import SwiftUI

struct FilterButton: View {
    let icon: String
    let title: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: AppTheme.FontSize.caption))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .frame(height: 28, alignment: .leading)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SidebarFilterButton: View {
    let icon: String
    let title: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        FilterButton(icon: icon, title: title, color: color, isSelected: isSelected, action: action)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        SidebarFilterButton(icon: "circle.fill", title: "Example", color: .blue, isSelected: true) {}
        SidebarFilterButton(icon: "circle.fill", title: "Example 2", color: .pink, isSelected: false) {}
    }
    .padding()
}
