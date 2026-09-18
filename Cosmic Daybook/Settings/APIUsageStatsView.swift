import SwiftUI

// MARK: - API Usage Stats View

/// Displays API usage statistics including call counts and estimated costs.
struct APIUsageStatsView: View {
    let tracker = APIUsageTracker.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Summary row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(tracker.entries.count)")
                        .font(.title2.weight(.semibold))
                    Text("Total API Calls")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "$%.4f", tracker.totalEstimatedCost))
                        .font(.title2.weight(.semibold).monospacedDigit())
                    Text("Est. Cost")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Detail rows
            HStack {
                Label("Today", systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(tracker.todayCallCount) calls")
                    .font(.caption.monospacedDigit())
            }

            HStack {
                Label("This Month", systemImage: "calendar.badge.clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(tracker.thisMonthCallCount) calls")
                    .font(.caption.monospacedDigit())
            }

            HStack {
                Label("Tokens", systemImage: "number")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(formatTokens(tracker.totalInputTokens)) in / \(formatTokens(tracker.totalOutputTokens)) out")
                    .font(.caption.monospacedDigit())
            }

            if !tracker.entries.isEmpty {
                Divider()

                Button(role: .destructive) {
                    tracker.clearHistory()
                } label: {
                    Label("Clear Usage History", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}
