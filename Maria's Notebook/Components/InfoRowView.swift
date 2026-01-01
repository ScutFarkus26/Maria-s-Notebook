import SwiftUI

struct InfoRowView: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Label {
                Text(title)
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
            }
            .labelStyle(.titleAndIcon)

            Spacer(minLength: 0)

            Text(value)
                .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(value))
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 14) {
        InfoRowView(icon: "calendar", title: "Birthday", value: "Jan 1, 2018")
        InfoRowView(icon: "gift", title: "Age", value: "6 years old")
    }
    .padding()
}
