import SwiftUI
import SwiftData

// MARK: - WorkModel Check-in Counts
extension WorkModel {
    /// Returns (completed, total, upcoming) counts for this work based on the current studentIDs.
    /// - completed: Number of students who have a completion/check-in recorded for this work.
    /// - total: Total number of students attached to this work.
    /// - upcoming: Students who have not yet checked in (total - completed), clamped to >= 0.
    func checkInCounts() -> (completed: Int, total: Int, upcoming: Int) {
        let total = studentIDs.count
        // Use existing API on WorkModel to avoid depending on relationship names
        let completed = studentIDs.reduce(into: 0) { partial, sid in
            if self.isStudentCompleted(sid) { partial += 1 }
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
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("\(counts.completed)/\(counts.total)")
                    .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.green.opacity(0.12))
            )

            if counts.upcoming > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .foregroundStyle(.orange)
                    Text("\(counts.upcoming)")
                        .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.orange.opacity(0.12))
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
}
