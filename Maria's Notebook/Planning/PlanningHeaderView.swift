import SwiftUI

struct PlanningHeaderView: View {
    let weekRange: String
    let onPrevWeek: () -> Void
    let onNextWeek: () -> Void
    let onToday: () -> Void
    let onAddNew: () -> Void
    var onAISuggest: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPrevWeek) { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)

            Text(weekRange)
                .font(AppTheme.ScaledFont.calloutSemibold)

            Button(action: onNextWeek) { Image(systemName: "chevron.right") }
                .buttonStyle(.plain)

            Spacer()

            Button("Today", action: onToday)
                .font(AppTheme.ScaledFont.captionSemibold)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.08), in: Capsule())

            Spacer(minLength: 0)

            if let onAISuggest {
                Button(action: onAISuggest) {
                    Label("AI Suggest", systemImage: "sparkles")
                }
                .buttonStyle(.plain)
            }

            Button(action: onAddNew) {
                Label("Add New", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, UIConstants.headerHorizontalPadding)
        .padding(.vertical, UIConstants.headerVerticalPadding)
    }
}
