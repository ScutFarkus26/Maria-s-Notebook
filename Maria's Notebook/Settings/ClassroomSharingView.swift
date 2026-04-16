import SwiftUI
import CloudKit
import OSLog

/// Settings view for managing classroom sharing.
///
/// Shows the current role, participant list, and actions for
/// sharing (lead guide) or leaving (assistant) a classroom.
struct ClassroomSharingView: View {
    @Environment(\.dependencies) private var dependencies

    @State private var sharingService: ClassroomSharingService?
    @State private var showingSharingSheet = false
    @State private var showingLeaveConfirmation = false
    @State private var showingStopSharingConfirmation = false
    @State private var errorMessage: String?

    private var service: ClassroomSharingService? { sharingService }

    var body: some View {
        VStack(spacing: 12) {
            roleGroup
            membersGroup
            actionsGroup

            if let error = errorMessage ?? service?.shareError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }
        .task {
            let svc = dependencies.classroomSharingService
            sharingService = svc
            try? svc.refreshParticipants()
        }
    }

    // MARK: - Role Display

    private var roleGroup: some View {
        SettingsGroup(title: "Your Role", systemImage: "person.badge.key.fill") {
            HStack(spacing: 12) {
                Image(systemName: roleIcon)
                    .font(.title2)
                    .foregroundStyle(roleColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(roleDisplayName)
                        .font(.headline)
                    Text(roleDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var roleIcon: String {
        switch service?.currentRole {
        case .leadGuide: return "star.circle.fill"
        case .assistant: return "person.circle.fill"
        case nil: return "person.circle"
        }
    }

    private var roleColor: Color {
        switch service?.currentRole {
        case .leadGuide: return .orange
        case .assistant: return .blue
        case nil: return .secondary
        }
    }

    private var roleDisplayName: String {
        switch service?.currentRole {
        case .leadGuide: return "Lead Guide"
        case .assistant: return "Assistant"
        case nil: return "Not Connected"
        }
    }

    private var roleDescription: String {
        switch service?.currentRole {
        case .leadGuide: return "Full access to all classroom data"
        case .assistant: return "Read access with limited write permissions"
        case nil: return "Set up sharing to collaborate"
        }
    }

    // MARK: - Members

    private var membersGroup: some View {
        SettingsGroup(title: "Classroom Members", systemImage: "person.2.fill", collapsible: true) {
            VStack(spacing: 8) {
                if let participants = service?.participants, !participants.isEmpty {
                    ForEach(participants, id: \.userIdentity.userRecordID) { participant in
                        participantRow(participant)
                    }
                } else {
                    Text("No participants yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func participantRow(_ participant: CKShare.Participant) -> some View {
        HStack(spacing: 10) {
            Image(systemName: participantIcon(for: participant))
                .foregroundStyle(participantColor(for: participant))

            VStack(alignment: .leading, spacing: 1) {
                Text(participantName(participant))
                    .font(.subheadline)
                Text(participantStatus(participant))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(participantPermission(participant))
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary)
                .clipShape(Capsule())
        }
    }

    private func participantName(_ participant: CKShare.Participant) -> String {
        if let name = participant.userIdentity.nameComponents {
            return PersonNameComponentsFormatter.localizedString(from: name, style: .default)
        }
        return "Unknown"
    }

    private func participantStatus(_ participant: CKShare.Participant) -> String {
        switch participant.acceptanceStatus {
        case .accepted: return "Joined"
        case .pending: return "Invited"
        case .removed: return "Removed"
        case .unknown: return "Unknown"
        @unknown default: return "Unknown"
        }
    }

    private func participantPermission(_ participant: CKShare.Participant) -> String {
        switch participant.permission {
        case .readWrite: return "Read & Write"
        case .readOnly: return "Read Only"
        case .none: return "None"
        case .unknown: return "Unknown"
        @unknown default: return "Unknown"
        }
    }

    private func participantIcon(for participant: CKShare.Participant) -> String {
        participant.role == .owner ? "star.circle.fill" : "person.circle.fill"
    }

    private func participantColor(for participant: CKShare.Participant) -> Color {
        switch participant.acceptanceStatus {
        case .accepted: return participant.role == .owner ? .orange : .blue
        case .pending: return .yellow
        default: return .secondary
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionsGroup: some View {
        if let svc = service {
            SettingsGroup(title: "Actions", systemImage: "square.and.arrow.up") {
                VStack(spacing: 8) {
                    if svc.canManageSharing() {
                        leadGuideActions
                        NavigationLink {
                            AssistantPermissionsView()
                        } label: {
                            Label("Assistant Permissions", systemImage: "lock.shield")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        assistantActions
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var leadGuideActions: some View {
        VStack(spacing: 8) {
            Button {
                showingSharingSheet = true
            } label: {
                Label(
                    service?.isSharing == true ? "Manage Sharing" : "Share Classroom",
                    systemImage: "square.and.arrow.up"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .sheet(isPresented: $showingSharingSheet) {
                if let svc = service, let share = svc.currentShare {
                    CloudSharingSheet(
                        share: share,
                        container: CKContainer.default(),
                        onDismiss: {
                            showingSharingSheet = false
                            try? svc.refreshParticipants()
                        }
                    )
                }
            }

            if service?.isSharing == true {
                Button(role: .destructive) {
                    showingStopSharingConfirmation = true
                } label: {
                    Label("Stop Sharing", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .confirmationDialog(
                    "Stop Sharing?",
                    isPresented: $showingStopSharingConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Stop Sharing", role: .destructive) {
                        // Stopping sharing is handled by the CloudSharingController
                        showingSharingSheet = true
                    }
                } message: {
                    Text("Assistants will lose access to classroom data.")
                }
            }
        }
    }

    private var assistantActions: some View {
        Button(role: .destructive) {
            showingLeaveConfirmation = true
        } label: {
            Label("Leave Classroom", systemImage: "rectangle.portrait.and.arrow.right")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .confirmationDialog(
            "Leave Classroom?",
            isPresented: $showingLeaveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Leave", role: .destructive) {
                Task {
                    do {
                        try await service?.leaveClassroom()
                    } catch {
                        errorMessage = AppErrorMessages.userMessage(for: error, context: "leaving the classroom")
                    }
                }
            }
        } message: {
            Text("Shared classroom data will be removed from this device.")
        }
    }
}
