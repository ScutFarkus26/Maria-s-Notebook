import SwiftUI
import CoreData

/// The week plan's pill for a work check-in that shares its lesson and purpose
/// with no other check-in that day; several that do draw as one
/// `GroupedWorkCheckInPill`.
///
/// The names come from the pill's `CalendarCheckInGroup`, which resolved them
/// for the whole visible range in three batched fetches. The pill used to look
/// them up itself — the work and then the child or the lesson, by id, for each
/// of its three reads of a name, so up to six fetches a pass — and it redraws
/// on every pass of its day column, including each insertion-index change
/// while something is dragged over the strip.
struct WorkCheckInPill: View {
    let checkIn: CDWorkCheckIn
    /// The lesson's name, or "Lesson " and the first six characters of the
    /// work's lesson id when the lesson has no name or is not on file.
    let workTitle: String
    /// The child's short name; empty when the work names no child on file.
    let studentName: String
    let isDulled: Bool
    let onTap: (() -> Void)?

    /// The pill for a group of one check-in, named as the group resolved it.
    init(group: CalendarCheckInGroup, isDulled: Bool = false, onTap: (() -> Void)? = nil) {
        checkIn = group.primary
        workTitle = group.lessonTitle
        studentName = group.studentNames.first ?? ""
        self.isDulled = isDulled
        self.onTap = onTap
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Top row: Name first, then lesson title
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if !studentName.trimmed().isEmpty {
                    Text(studentName)
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Text(workTitle)
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if checkIn.studentInitiated {
                    Spacer(minLength: 4)
                    Image(systemName: "person.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Student requested")
                }
            }
            // Second row: purpose (e.g., Progress Check, Due Date)
            if !checkIn.purpose.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: purposeIcon)
                        .foregroundStyle(.secondary)
                    Text(checkIn.purpose)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(
            UIConstants.CornerRadius.large,
            fill: Color.primary.opacity(UIConstants.OpacityConstants.veryFaint),
            stroke: Color.primary.opacity(UIConstants.OpacityConstants.subtle),
            lineWidth: 1
        )
        .opacity(isDulled ? 0.5 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }

    // MARK: - Data Helpers

    private var purposeIcon: String {
        let purpose = checkIn.purpose.lowercased()
        if purpose.contains("progress") || purpose.contains("check") {
            return "checkmark.circle"
        } else if purpose.contains("due") {
            return "calendar.badge.exclamationmark"
        } else if purpose.contains("assessment") {
            return "chart.bar"
        } else if purpose.contains("follow") {
            return "arrow.turn.down.right"
        } else {
            return "calendar"
        }
    }
}
