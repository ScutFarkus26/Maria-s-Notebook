import SwiftUI

struct InboxStatusSection: View {
    @Binding var scheduledFor: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "tray")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 16))
                Text("Inbox Status")
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .foregroundStyle(.blue)
                    .font(.system(size: 14))
                Text("Scheduled: \(scheduleStatusText)")
                    .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                    .foregroundColor(.blue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.blue.opacity(0.1))
            )

            Button {
                scheduledFor = nil
            } label: {
                Label("Remove from Schedule", systemImage: "xmark.circle")
                    .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private var unscheduledView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))
                Text("Unscheduled")
                    .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
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

    private var scheduleStatusText: String {
        guard let date = scheduledFor else { return "Not Scheduled Yet" }
        let df = DateFormatter()
        df.setLocalizedDateFormatFromTemplate("EEEE, MMM d")
        let datePart = df.string(from: date)
        let hour = Calendar.current.component(.hour, from: date)
        let period = hour < 12 ? "Morning" : "Afternoon"
        return "\(datePart) in the \(period)"
    }
}
