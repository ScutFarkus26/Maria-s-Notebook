import SwiftUI

// MARK: - Sync History Log View

/// Displays a chronological log of recent sync events.
struct SyncHistoryLogView: View {
    let logger: SyncEventLogger

    var body: some View {
        Group {
            if logger.events.isEmpty {
                ContentUnavailableView(
                    "No Sync History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Sync events will appear here as they occur.")
                )
            } else {
                List {
                    ForEach(logger.events) { event in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(statusColor(event.status))
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(event.type.capitalized)
                                        .font(.caption2.weight(.medium))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule().fill(typeColor(event.type).opacity(0.15))
                                        )
                                        .foregroundStyle(typeColor(event.type))
                                    Text(event.message)
                                        .font(.subheadline)
                                        .lineLimit(2)
                                }
                                HStack(spacing: 0) {
                                    Text(event.timestamp, style: .relative)
                                    Text(" ago")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Sync History")
        .inlineNavigationTitle()
        .toolbar {
            if !logger.events.isEmpty {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Clear", role: .destructive) {
                        logger.clearHistory()
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "success": return AppColors.success
        case "error": return AppColors.destructive
        case "started": return AppColors.info
        default: return .secondary
        }
    }

    private func typeColor(_ type: String) -> Color {
        switch type {
        case "cloudkit": return .blue
        case "calendar": return .orange
        case "reminders": return .purple
        default: return .secondary
        }
    }
}
