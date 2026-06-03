import SwiftUI
import CloudKit
import CoreData
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
    @State private var showingUnrecoverableSheet = false
    @State private var errorMessage: String?
    @State private var isPreparingShare = false

    private var service: ClassroomSharingService? { sharingService }
    private var zoneRepair: SharedStoreZoneRepair { dependencies.sharedStoreZoneRepair }

    var body: some View {
        VStack(spacing: 12) {
            syncStatusBanner
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
        .sheet(isPresented: $showingUnrecoverableSheet) {
            unrecoverableOrphansSheet
        }
    }

    // MARK: - Sync Status Banner

    @ViewBuilder
    private var syncStatusBanner: some View {
        if service?.currentRole == .leadGuide {
            if service?.isSharing == false, zoneRepair.orphanCount > 0 {
                bannerCard(
                    icon: "exclamationmark.triangle.fill",
                    tint: .orange,
                    title: "\(zoneRepair.orphanCount) record(s) waiting to sync",
                    body: "Until you share your classroom, this data stays on this device only. " +
                        "Tap Share Classroom below to enable CloudKit sync."
                )
            } else if service?.isSharing == true, !zoneRepair.lastUnrecoverableOrphans.isEmpty {
                bannerCard(
                    icon: "exclamationmark.octagon.fill",
                    tint: .red,
                    title: "\(zoneRepair.lastUnrecoverableOrphans.count) record(s) failed to sync",
                    body: "These records couldn't be attached to your classroom share. Tap Repair Sync below to retry."
                )
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
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tint.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Unrecoverable Orphans Sheet

    private var unrecoverableOrphansSheet: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(zoneRepair.orphansByEntity.sorted(by: { $0.key < $1.key }), id: \.key) { entity, count in
                        HStack {
                            Text(entity)
                            Spacer()
                            Text("\(count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Orphans by entity")
                } footer: {
                    Text(
                        "Last checked: " +
                        (zoneRepair.lastRunAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "never")
                    )
                }

                if !zoneRepair.lastUnrecoverableOrphans.isEmpty {
                    Section("Unrecoverable record IDs") {
                        ForEach(zoneRepair.lastUnrecoverableOrphans, id: \.self) { id in
                            Text(id.uriRepresentation().lastPathComponent)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Sync Diagnostics")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingUnrecoverableSheet = false }
                }
            }
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
                Task { await prepareAndPresentSharingSheet() }
            } label: {
                HStack(spacing: 8) {
                    if isPreparingShare {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Label(
                        service?.isSharing == true ? "Manage Sharing" : "Share Classroom",
                        systemImage: "square.and.arrow.up"
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(isPreparingShare)
            .sheet(isPresented: $showingSharingSheet) {
                if let svc = service, let share = svc.currentShare {
                    CloudSharingSheet(
                        share: share,
                        container: CKContainer.default(),
                        onShareSaved: {
                            // Force a synchronous refresh so the
                            // false→true transition fires and triggers
                            // SharedStoreZoneRepair without waiting for
                            // Core Data to surface the new share.
                            _ = try? svc.fetchExistingShare()
                        },
                        onDismiss: {
                            showingSharingSheet = false
                            try? svc.refreshParticipants()
                        }
                    )
                }
            }

            if service?.isSharing == true {
                repairSyncButton

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

    @ViewBuilder
    private var repairSyncButton: some View {
        Button {
            Task {
                // Manual variant — resets the circuit breaker so user-driven
                // retries always get a fresh attempt even after a recent
                // auto-skip.
                await zoneRepair.runManual(coreDataStack: dependencies.coreDataStack)
                if zoneRepair.orphanCount == 0, zoneRepair.lastUnrecoverableOrphans.isEmpty {
                    ToastService.shared.showSuccess("Sync repair complete")
                } else if !zoneRepair.lastUnrecoverableOrphans.isEmpty {
                    showingUnrecoverableSheet = true
                } else {
                    ToastService.shared.showInfo("No sync errors detected")
                }
            }
        } label: {
            HStack {
                Label("Repair Sync Errors", systemImage: "arrow.triangle.2.circlepath")
                if zoneRepair.orphanCount > 0 {
                    Spacer()
                    Text("\(zoneRepair.orphanCount)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.18))
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(zoneRepair.repairInProgress)
        .overlay(alignment: .trailing) {
            if zoneRepair.repairInProgress {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 8)
            }
        }
    }

    private func prepareAndPresentSharingSheet() async {
        guard let svc = service else { return }
        isPreparingShare = true
        defer { isPreparingShare = false }
        do {
            _ = try await svc.prepareShareForPresentation(coreDataStack: dependencies.coreDataStack)
            errorMessage = nil
            showingSharingSheet = true
        } catch {
            let ns = error as NSError
            Logger.app(category: "ClassroomSharing").error("""
                Share Classroom failed — \
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
