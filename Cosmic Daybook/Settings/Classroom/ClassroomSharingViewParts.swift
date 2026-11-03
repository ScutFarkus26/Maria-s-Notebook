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

/// The top of the Classroom pane: the state of the classroom share for the
/// lead guide, in plain words. The "not in the share" count is read-only: it
/// shows drift, it never fixes it.
struct ClassroomShareStatusCard: View {
    let service: ClassroomSharingService?
    let contents: ClassroomShareContents?

    @ViewBuilder
    var body: some View {
        if service?.currentRole == .leadGuide {
            if service?.isSharing != true {
                if FirstDownloadGate.isPending() {
                    ClassroomShareBanner(
                        icon: "icloud.and.arrow.down",
                        tint: .secondary,
                        title: "Still downloading from iCloud",
                        message: "Classroom sharing can be set up once the notebook has finished downloading."
                    )
                } else {
                    ClassroomShareBanner(
                        icon: "person.2.slash",
                        tint: .secondary,
                        title: "Not shared yet",
                        message: Self.notSharedMessage
                    )
                }
            } else if let contents {
                if contents.outside > 0 {
                    ClassroomShareBanner(
                        icon: "exclamationmark.triangle.fill",
                        tint: AppColors.warning,
                        title: Self.outsideTitle(contents.outside),
                        message: Self.outsideMessage(contents)
                    )
                } else {
                    ClassroomShareBanner(
                        icon: "checkmark.circle.fill",
                        tint: AppColors.success,
                        title: "Classroom shared",
                        message: "The share holds \(contents.summary)."
                    )
                }
            }
        }
    }

    private static func outsideTitle(_ count: Int) -> String {
        count == 1
            ? "1 classroom item isn't shared with your assistant yet"
            : "\(count.formatted()) classroom items aren't shared with your assistant yet"
    }

    /// What the share holds, then which of them can't be added (in an old
    /// share, bug hunt 2026-11-02, #32) and, on iPhone and iPad, where the
    /// rest are added.
    private static func outsideMessage(_ contents: ClassroomShareContents) -> String {
        var message = "Your assistant can't see them. The share holds \(contents.summary)."
        if let elsewhere = contents.inOtherShareLine { message += " " + elsewhere }
        #if !os(macOS)
        if contents.addable > 0 {
            message += contents.inOtherShare > 0 ? " Add the rest" : " Add them"
            message += " on your Mac, in Settings › Classroom."
        }
        #endif
        return message
    }

    /// Setting up is on the Mac only: two devices setting up at once made two
    /// share zones (bug hunt 2026-11-02, #30).
    #if os(macOS)
    private static let notSharedMessage = "Set up classroom sharing once, here on your Mac, to give an assistant "
        + "your class list, attendance and school calendar."
    #else
    private static let notSharedMessage = "Set up classroom sharing on your Mac, in Settings › Classroom, to give "
        + "an assistant your class list, attendance and school calendar."
    #endif
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

    /// The words the Manage Sharing sheet shows. It adds everyone as "Can
    /// make changes"; "View only" is someone added that way before 2026-11.
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
