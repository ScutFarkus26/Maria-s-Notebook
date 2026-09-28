import SwiftUI
import CloudKit
import CoreData
import OSLog

/// Settings view for managing classroom sharing.
///
/// Shows the current role, what the classroom share holds, the participant
/// list, and actions for setting up sharing and inviting (lead guide) or
/// leaving (assistant). The classroom has one share, set up once on purpose
/// with Set Up Classroom Sharing; nothing here creates or repairs a share on
/// its own.
struct ClassroomSharingView: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(\.scenePhase) private var scenePhase

    @State private var sharingService: ClassroomSharingService?
    @State private var showingSharingSheet = false
    @State private var showingLeaveConfirmation = false
    @State private var showingStopSharingConfirmation = false
    @State private var showingSetupConfirmation = false
    @State private var errorMessage: String?
    @State private var resultMessage: String?
    @State private var isPreparingShare = false
    @State private var isSettingUp = false
    @State private var contents: ClassroomShareContents?

    private var service: ClassroomSharingService? { sharingService }

    var body: some View {
        VStack(spacing: 12) {
            shareStatusCard
            roleGroup
            membersGroup
            actionsGroup

            if let resultMessage {
                Text(resultMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
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
            // Live participant updates only while this screen is on screen.
            svc.startObservingParticipants()
            await refreshContents()
        }
        .onDisappear {
            sharingService?.stopObservingParticipants()
        }
        // What the share holds is read when the screen appears, when the scene
        // comes back, and after setup — not on every remote change: it reads
        // every classroom record's object ID and asks CloudKit about them.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshContents() } }
        }
    }

    // MARK: - What the share holds

    private func refreshContents() async {
        guard scenePhase == .active, service?.currentRole == .leadGuide else { return }
        contents = await ClassroomSharingService.shareContents(coreDataStack: dependencies.coreDataStack)
    }

    /// Plain-language state of the classroom share for the lead guide. The
    /// "not in the share" count is read-only: it shows drift, it never fixes it.
    @ViewBuilder
    private var shareStatusCard: some View {
        if service?.currentRole == .leadGuide {
            if service?.isSharing != true {
                if FirstDownloadGate.isPending() {
                    bannerCard(
                        icon: "icloud.and.arrow.down",
                        tint: .secondary,
                        title: "Still downloading from iCloud",
                        body: "Classroom sharing can be set up once the notebook has finished downloading."
                    )
                } else {
                    bannerCard(
                        icon: "person.2.slash",
                        tint: .secondary,
                        title: "Not shared yet",
                        body: "Set up classroom sharing once, on this Mac, to give an assistant your class " +
                            "list, attendance and school calendar."
                    )
                }
            } else if let contents {
                if contents.outside > 0 {
                    bannerCard(
                        icon: "exclamationmark.triangle.fill",
                        tint: .orange,
                        title: "\(contents.outside) classroom record(s) aren't in the classroom share",
                        body: "Your assistant can't see them. The share holds \(contents.summary)."
                    )
                } else {
                    bannerCard(
                        icon: "checkmark.circle.fill",
                        tint: .green,
                        title: "Classroom shared",
                        body: "The share holds \(contents.summary)."
                    )
                }
            }
        }
    }

    private func bannerCard(icon: String, tint: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .surface(
            UIConstants.CornerRadius.control,
            fill: tint.opacity(0.12),
            stroke: tint.opacity(0.4),
            lineWidth: 1,
            style: .continuous
        )
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
        let isYou = participant.userIdentity.userRecordID?.recordName != nil
            && participant.userIdentity.userRecordID?.recordName == service?.currentUserRecordName

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

    @ViewBuilder
    private var leadGuideActions: some View {
        VStack(spacing: 8) {
            if service?.isSharing == true {
                manageSharingButton
                if (contents?.outside ?? 0) > 0 {
                    setUpButton(title: "Add Them to the Share", prominent: false)
                }
                stopSharingButton
            } else {
                setUpButton(title: "Set Up Classroom Sharing", prominent: true)
            }
        }
        .confirmationDialog(
            "Set up classroom sharing?",
            isPresented: $showingSetupConfirmation,
            titleVisibility: .visible
        ) {
            Button("Set Up") { Task { await setUpSharing() } }
        } message: {
            Text(
                "Your students, attendance, school calendar and locked days go into one classroom share. " +
                "Lessons, notes, work and everything else stay yours alone. Keep the app open until it finishes."
            )
        }
    }

    @ViewBuilder
    private func setUpButton(title: String, prominent: Bool) -> some View {
        let button = Button {
            showingSetupConfirmation = true
        } label: {
            HStack(spacing: 8) {
                if isSettingUp {
                    ProgressView().controlSize(.small)
                }
                Label(title, systemImage: "person.2.badge.plus")
                    .frame(maxWidth: .infinity)
            }
        }
        .disabled(isSettingUp || FirstDownloadGate.isPending())
        if prominent {
            button.buttonStyle(.borderedProminent).controlSize(.regular)
        } else {
            button.buttonStyle(.bordered).controlSize(.small)
        }
    }

    private var manageSharingButton: some View {
        Button {
            Task { await prepareAndPresentSharingSheet() }
        } label: {
            HStack(spacing: 8) {
                if isPreparingShare {
                    ProgressView().controlSize(.small)
                }
                Label("Manage Sharing", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .disabled(isPreparingShare)
        .sheet(isPresented: $showingSharingSheet) {
            sharingSheet
        }
    }

    @ViewBuilder
    private var sharingSheet: some View {
        #if os(macOS)
        if let svc = service {
            ClassroomMembersSheet(service: svc, contents: contents) {
                showingSharingSheet = false
                try? svc.refreshParticipants()
            }
        }
        #else
        if let svc = service, let share = svc.currentShare {
            CloudSharingSheet(
                share: share,
                container: CloudKitConfigurationService.container,
                onShareSaved: {
                    // Resync right away rather than waiting for Core Data to
                    // surface the saved share.
                    _ = try? svc.fetchExistingShare()
                },
                onStopSharing: {
                    // Owner ended the share inside the sheet — resync
                    // published share state immediately instead of reporting
                    // the dead share until the next launch.
                    svc.handleSharingStopped()
                },
                onDismiss: {
                    showingSharingSheet = false
                    try? svc.refreshParticipants()
                }
            )
        }
        #endif
    }

    private var stopSharingButton: some View {
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
                #if os(macOS)
                // The Mac has no system sharing UI to end the share in, and
                // the share itself has to stay (a new one would be a second
                // zone) — so remove everyone.
                Task {
                    do {
                        try await service?.removeAllMembers()
                    } catch {
                        errorMessage = AppErrorMessages.userMessage(for: error, context: "stopping sharing")
                    }
                }
                #else
                // Stopping sharing is handled by the CloudSharingController
                showingSharingSheet = true
                #endif
            }
        } message: {
            Text("Assistants will lose access to classroom data.")
        }
    }

    private func setUpSharing() async {
        guard let svc = service else { return }
        isSettingUp = true
        defer { isSettingUp = false }
        errorMessage = nil
        resultMessage = nil
        do {
            let report = try await svc.setUpClassroomSharing(coreDataStack: dependencies.coreDataStack)
            contents = report.contents
            try? svc.refreshParticipants()
            var message = report.created ? "Classroom share created. " : ""
            message += "\(report.attached) record(s) added."
            if let contents = report.contents { message += " The share holds \(contents.summary)." }
            if report.failed > 0 {
                message += " \(report.failed) couldn't be added"
                message += report.stoppedBecause.map { " (\($0))" } ?? ""
                message += "; try again later."
            }
            resultMessage = message
        } catch {
            let ns = error as NSError
            Logger.classroomSharing.error("""
                Set Up Classroom Sharing failed — \
                domain=\(ns.domain, privacy: .public) \
                code=\(ns.code, privacy: .public) \
                description=\(ns.localizedDescription, privacy: .public)
                """)
            errorMessage = AppErrorMessages.userMessage(for: error, context: "setting up classroom sharing")
            await refreshContents()
        }
    }

    private func prepareAndPresentSharingSheet() async {
        guard let svc = service else { return }
        isPreparingShare = true
        defer { isPreparingShare = false }
        do {
            let (_, shareContents) = try await svc.shareForInvitations(coreDataStack: dependencies.coreDataStack)
            contents = shareContents
            errorMessage = nil
            showingSharingSheet = true
        } catch {
            let ns = error as NSError
            Logger.classroomSharing.error("""
                Manage Sharing refused — \
                domain=\(ns.domain, privacy: .public) \
                code=\(ns.code, privacy: .public) \
                description=\(ns.localizedDescription, privacy: .public)
                """)
            errorMessage = AppErrorMessages.userMessage(for: error, context: "sharing your classroom")
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
