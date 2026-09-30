import SwiftUI

// MARK: - Sync History Log View

/// Displays a chronological log of recent sync events.
struct SyncHistoryLogView: View {
    let logger: SyncEventLogger
    @State private var showingClearConfirmation = false

    var body: some View {
        Group {
            if logger.events.isEmpty {
                ContentUnavailableView(
                    "No sync history yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Each time iCloud, Calendar or Reminders syncs, it shows up here.")
                )
            } else {
                List {
                    ForEach(logger.events) { event in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(statusColor(event.status))
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                                HStack(spacing: AppTheme.Spacing.verySmall) {
                                    Text(typeName(event.type))
                                        .font(.caption2.weight(.medium))
                                        .padding(.horizontal, AppTheme.Spacing.verySmall)
                                        .padding(.vertical, AppTheme.Spacing.xxsmall)
                                        .capsuleFill(typeColor(event.type).opacity(UIConstants.OpacityConstants.accent))
                                        .foregroundStyle(typeColor(event.type))
                                    Text(event.message)
                                        .font(.subheadline)
                                        .lineLimit(2)
                                    if event.count > 1 {
                                        Text("×\(event.count)")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                            .accessibilityLabel("repeated \(event.count) times")
                                    }
                                }
                                Text(event.timestamp.formatted(.relative(presentation: .named)))
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
                        showingClearConfirmation = true
                    }
                    .font(.caption)
                }
            }
        }
        .confirmationDialog(
            "Clear sync history?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear history", role: .destructive) {
                logger.clearHistory()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This empties the list of recent sync activity on this device. Your notebook isn't changed.")
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

    /// The pill's name for a logged sync type ("cloudkit" reads as "iCloud").
    private func typeName(_ type: String) -> String {
        switch type {
        case "cloudkit": return "iCloud"
        case "calendar": return "Calendar"
        case "reminders": return "Reminders"
        default: return type.capitalized
        }
    }

    private func typeColor(_ type: String) -> Color {
        switch type {
        case "cloudkit": return AppColors.info
        case "calendar": return AppColors.warning
        case "reminders": return .purple
        default: return .secondary
        }
    }
}
