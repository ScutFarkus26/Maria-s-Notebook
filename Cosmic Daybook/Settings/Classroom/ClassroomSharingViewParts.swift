import SwiftUI
import CloudKit
import CoreData

// MARK: - Classroom Sharing Parts

// The pieces the Classroom pane (`ClassroomSharingView`) is built from.

/// A tinted banner at the top of the Classroom pane: what state the share is in.
struct ClassroomShareBanner: View {
    let icon: String
    let tint: Color
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(AppTheme.Spacing.compact)
        .surface(
            UIConstants.CornerRadius.control,
            fill: tint.opacity(0.12),
            stroke: tint.opacity(0.4),
            lineWidth: 1,
            style: .continuous
        )
    }
}

/// One person in the classroom share: who, their role and whether they've
/// joined, and what they're allowed to do.
struct ClassroomParticipantRow: View {
    let participant: CKShare.Participant
    let isYou: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: participant.role == .owner ? "star.circle.fill" : "person.circle.fill")
                .foregroundStyle(iconColor)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.subheadline)
                Text(statusLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(permission)
                .font(.caption2)
                .padding(.horizontal, AppTheme.Spacing.verySmall)
                .padding(.vertical, AppTheme.Spacing.xxsmall)
                .background(.quaternary)
                .clipShape(Capsule())
        }
        .accessibilityElement(children: .combine)
    }

    private var name: String {
        if let name = participant.userIdentity.nameComponents {
            let formatted = PersonNameComponentsFormatter
                .localizedString(from: name, style: .default)
                .trimmed()
            if !formatted.isEmpty {
                return isYou ? "\(formatted) (you)" : formatted
            }
        }

        // CloudKit withholds your own name components entirely, and withholds
        // an invitee's until they accept — so both rows would otherwise render
        // blank and be impossible to tell apart.
        return isYou ? "You" : "Name not shared"
    }

    /// "Assistant · Invited", "Lead guide · Joined".
    private var statusLine: String {
        let role = participant.role == .owner ? "Lead guide" : "Assistant"
        let status: String
        switch participant.acceptanceStatus {
        case .accepted: status = "Joined"
        case .pending: status = "Invited"
        case .removed: status = "Removed"
        case .unknown: status = "Unknown"
        @unknown default: status = "Unknown"
        }
        return "\(role) · \(status)"
    }

    /// The same two words the Mac's Manage Sharing sheet offers.
    private var permission: String {
        switch participant.permission {
        case .readWrite: return "Can make changes"
        case .readOnly: return "View only"
        case .none: return "No access"
        case .unknown: return "Unknown"
        @unknown default: return "Unknown"
        }
    }

    private var iconColor: Color {
        switch participant.acceptanceStatus {
        case .accepted: return participant.role == .owner ? .orange : .blue
        case .pending: return AppColors.warning
        default: return .secondary
        }
    }
}

/// Which role this device plays in the classroom, and what that role does.
struct ClassroomRoleSummary: View {
    let role: CDClassroomMembership.ClassroomRole?

    var body: some View {
        HStack(spacing: AppTheme.Spacing.compact) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                Text(displayName)
                    .font(.headline)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var icon: String {
        switch role {
        case .leadGuide: return "star.circle.fill"
        case .assistant: return "person.circle.fill"
        case nil: return "person.circle"
        }
    }

    private var color: Color {
        switch role {
        case .leadGuide: return .orange
        case .assistant: return .blue
        case nil: return .secondary
        }
    }

    private var displayName: String {
        switch role {
        case .leadGuide: return "Lead guide"
        case .assistant: return "Assistant"
        case nil: return "Not connected"
        }
    }

    private var summary: String {
        switch role {
        case .leadGuide: return "You set up sharing, invite your assistant and lock attendance days"
        case .assistant: return "You take attendance on any day the lead guide hasn't locked"
        case nil: return "Set up sharing to work with an assistant"
        }
    }
}

/// Classroom › Your assistant: what an assistant can do and see, said once.
/// There is nothing to switch: the Daybook Assistant takes attendance and
/// nothing else, and the rest of the notebook never reaches the classroom share.
struct ClassroomAssistantCard: View {
    let service: ClassroomSharingService?
    let contents: ClassroomShareContents?

    @ViewBuilder
    var body: some View {
        if service?.currentRole == .leadGuide {
            SettingsGroup(title: "Your assistant", systemImage: "person.crop.circle.badge.checkmark") {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    Text(
                        "Your assistant can take attendance on any day you haven't locked. " +
                        "Lessons, notes and work stay yours alone."
                    )
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)

                    Label(assistantSeesText, systemImage: "eye")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// The share's own counts once it exists; the kinds of record before then.
    private var assistantSeesText: String {
        if service?.isSharing == true, let contents {
            return "What your assistant sees: \(contents.summary)."
        }
        return "What your assistant sees: your students, attendance, locked days and school calendar."
    }
}

/// Classroom › Members: everyone on the classroom share.
struct ClassroomMembersCard: View {
    let service: ClassroomSharingService?

    var body: some View {
        SettingsGroup(title: "Members", systemImage: "person.2.fill", collapsible: true) {
            VStack(spacing: AppTheme.Spacing.small) {
                if let participants = service?.participants, !participants.isEmpty {
                    ForEach(participants, id: \.userIdentity.userRecordID) { participant in
                        ClassroomParticipantRow(
                            participant: participant,
                            isYou: participant.participantID == service?.currentUserParticipantID
                        )
                    }
                } else {
                    Text("No members yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.small)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
