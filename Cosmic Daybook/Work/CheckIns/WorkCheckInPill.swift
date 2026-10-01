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

    /// One line: the purpose as an icon, the child, then the lesson. The
    /// grouped pill has the same shape, so a day's checks line up.
    ///
    /// It was two rows, with the purpose spelled out underneath, when checks
    /// had a lane of their own beside the presentations. They now sit under
    /// the presentations in a day a fifth of the strip wide, and a day of a
    /// dozen checks at two rows each pushed the lessons off the top. The
    /// purpose is still there, spelled out, in the tooltip and to VoiceOver.
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: CheckInReason.iconName(forStoredPurpose: checkIn.purpose))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            if !studentName.trimmed().isEmpty {
                Text(studentName)
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            Text(workTitle)
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if checkIn.studentInitiated {
                Image(systemName: "person.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Student requested")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(
            UIConstants.CornerRadius.medium,
            fill: Color.primary.opacity(UIConstants.OpacityConstants.veryFaint),
            stroke: Color.primary.opacity(UIConstants.OpacityConstants.subtle),
            lineWidth: 1
        )
        .opacity(isDulled ? 0.5 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .help(helpText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(helpText)
    }

    // MARK: - Data Helpers

    private var purposeTitle: String {
        CheckInReason.displayName(forStoredPurpose: checkIn.purpose)
    }

    /// "Progress Check: Maya S, Golden Beads" — the row with nothing cut off.
    private var helpText: String {
        let who = [studentName.trimmed(), workTitle]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        return purposeTitle.isEmpty ? who : "\(purposeTitle): \(who)"
    }
}
