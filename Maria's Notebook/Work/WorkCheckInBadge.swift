import SwiftUI
import SwiftData

// MARK: - WorkModel Check-in Counts
extension WorkModel {
    /// Returns (completed, total, upcoming) counts for this work based on current participants.
    /// - completed: Number of participants who have completed this work.
    /// - total: Total number of participants attached to this work.
    /// - upcoming: Participants who have not yet completed (total - completed), clamped to >= 0.
    func checkInCounts() -> (completed: Int, total: Int, upcoming: Int) {
        let list = participants ?? []
        let total = list.count
        let completed = list.reduce(0) { partial, p in
            partial + (p.completedAt != nil ? 1 : 0)
        }
        let upcoming = max(0, total - completed)
        return (completed, total, upcoming)
    }
}

// MARK: - Compact Summary View
/// A compact visual summary of a work's check-ins.
/// Shows completed vs total (e.g., 2/5) and, if any are remaining, an
/// upcoming badge indicating how many check-ins are left.
struct WorkCheckInSummary: View {
    let work: WorkModel

    private var counts: (completed: Int, total: Int, upcoming: Int) {
        work.checkInCounts()
    }

    var body: some View {
        HStack(spacing: 8) {
            statusBadge(
                status: .completed,
                text: "\(counts.completed)/\(counts.total)"
            )

            if counts.upcoming > 0 {
                statusBadge(
                    status: .scheduled,
                    text: "\(counts.upcoming)"
                )
                .accessibilityLabel("Upcoming check-ins: \(counts.upcoming)")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            counts.upcoming > 0 ?
            "Check-ins: \(counts.completed) of \(counts.total) completed. \(counts.upcoming) upcoming." :
            "Check-ins: \(counts.completed) of \(counts.total) completed."
        )
    }

    private func statusBadge(status: WorkCheckInStatus, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: status.iconName)
                .foregroundStyle(status.color)
            Text(text)
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(status.color.opacity(0.12))
        )
    }
}
