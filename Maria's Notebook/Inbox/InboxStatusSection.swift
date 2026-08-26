import SwiftUI

struct InboxStatusSection: View {
    @Binding var scheduledFor: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            HStack(spacing: AppTheme.Spacing.small) {
                Image(systemName: "tray")
                    .foregroundStyle(.secondary)
                    .font(.system(size: UIConstants.CardSize.iconSize))
                Text("Inbox Status")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
            }

            if scheduledFor != nil {
                scheduledView
            } else {
                unscheduledView
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scheduledView: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack(spacing: AppTheme.Spacing.small) {
                Image(systemName: "calendar")
                    .foregroundStyle(.blue)
                    .font(.system(size: UIConstants.CardSize.iconSize))
                Text("Scheduled")
                    .font(AppTheme.ScaledFont.body)
                    .foregroundStyle(.blue)
            }
            .padding(.horizontal, AppTheme.Spacing.compact)
            .padding(.vertical, AppTheme.Spacing.small)
            .background(
                RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous)
                    .fill(Color.blue.opacity(UIConstants.OpacityConstants.light))
            )

            OptionalDatePicker(
                toggleLabel: "Change Date",
                dateLabel: "Schedule For",
                date: $scheduledFor,
                displayedComponents: [.date, .hourAndMinute],
                defaultHour: 9
            )

            Button {
                scheduledFor = nil
            } label: {
                Label("Remove from Schedule", systemImage: "xmark.circle")
                    .font(AppTheme.ScaledFont.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private var unscheduledView: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack(spacing: AppTheme.Spacing.small) {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                    .font(.system(size: UIConstants.CardSize.iconSize))
                Text("Unscheduled")
                    .font(AppTheme.ScaledFont.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, AppTheme.Spacing.compact)
            .padding(.vertical, AppTheme.Spacing.small)
            .background(
                RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous)
                    .fill(Color.secondary.opacity(UIConstants.OpacityConstants.faint))
            )

            OptionalDatePicker(
                toggleLabel: "Schedule Lesson",
                dateLabel: "Schedule For",
                date: $scheduledFor,
                displayedComponents: [.date, .hourAndMinute],
                defaultHour: 9
            )
        }
    }

}
