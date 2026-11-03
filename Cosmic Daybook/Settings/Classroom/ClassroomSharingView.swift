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
    @State private var isStoppingSharing = false
    @State private var contents: ClassroomShareContents?

    private var service: ClassroomSharingService? { sharingService }

    var body: some View {
        VStack(spacing: SettingsStyle.groupSpacing) {
            ClassroomShareStatusCard(service: service, contents: contents)
            if service?.currentRole == .leadGuide, service?.isSharing == true {
                ClassroomLastYearCard(contents: contents) { await refreshContents() }
                if ClassroomAttendanceCatchUp.isAvailableHere {
                    ClassroomAttendanceCatchUpCard { await refreshContents() }
                }
            }
            roleGroup
            if service?.currentRole == .leadGuide {
                ClassroomYourNameCard()
            }
            ClassroomAssistantCard(service: service, contents: contents)
            ClassroomMembersCard(service: service)
            sharingGroup

            if let resultMessage {
                Text(resultMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppTheme.Spacing.xsmall)
            }
            if let error = errorMessage ?? service?.shareError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(AppColors.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppTheme.Spacing.xsmall)
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

    /// Not only while the scene is active: the screen's first read runs as it
    /// appears, often before then, and the status banner and the Last Year
    /// card stayed empty until the next phase change (bug hunt 2026-11-02, #41).
    private func refreshContents() async {
        guard service?.currentRole == .leadGuide else { return }
        contents = await ClassroomSharingService.shareContents(coreDataStack: dependencies.coreDataStack)
    }

    // MARK: - Role Display

    private var roleGroup: some View {
        SettingsGroup(title: "Your role", systemImage: "person.badge.key.fill") {
            ClassroomRoleSummary(role: service?.currentRole)
        }
    }

    // MARK: - Sharing

    @ViewBuilder
    private var sharingGroup: some View {
        if let svc = service {
            if svc.canManageSharing() {
                SettingsGroup(title: "Sharing", systemImage: "square.and.arrow.up") {
                    leadGuideActions
                        .frame(maxWidth: .infinity)
                }
            } else {
                SettingsGroup(title: "Your classroom", systemImage: "rectangle.portrait.and.arrow.right") {
                    assistantActions
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private var leadGuideActions: some View {
        VStack(spacing: AppTheme.Spacing.small) {
            // Setting up, and adding to the share, run on the Mac only (#30).
            // Records in an old share can't be added (#32).
            if service?.isSharing == true {
                manageSharingButton
                #if os(macOS)
                if (contents?.addable ?? 0) > 0 {
                    setUpButton(title: "Add them to the share", prominent: false)
                }
                #endif
                stopSharingButton
            } else {
                #if os(macOS)
                setUpButton(title: "Set up classroom sharing", prominent: true)
                #else
                Text("Classroom sharing is set up on your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #endif
            }
        }
        .confirmationDialog(
            "Set up classroom sharing?",
            isPresented: $showingSetupConfirmation,
            titleVisibility: .visible
        ) {
            Button("Set up") { Task { await setUpSharing() } }
        } message: {
            Text(
                "This school year's students and attendance, your school calendar and locked days go into one " +
                "classroom share. " +
                "Lessons, notes, work and everything else stay yours alone. Keep the app open until it finishes."
            )
        }
    }

    @ViewBuilder
    private func setUpButton(title: String, prominent: Bool) -> some View {
        let button = Button {
            showingSetupConfirmation = true
        } label: {
            HStack(spacing: AppTheme.Spacing.small) {
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
            HStack(spacing: AppTheme.Spacing.small) {
                if isPreparingShare {
                    ProgressView().controlSize(.small)
                }
                Label("Manage sharing", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .disabled(isPreparingShare)
        .sheet(isPresented: $showingSharingSheet) {
            if let svc = service {
                // The app's own members sheet on every device: the system
                // sharing sheet's Stop Sharing deletes the share.
                ClassroomMembersSheet(service: svc, contents: contents) {
                    showingSharingSheet = false
                    Task { await svc.refreshShareInBackground() }
                }
            }
        }
    }

    /// Removes everyone, so it asks first. The share itself stays, on every
    /// device: a new one would be a second zone, and the pin would name one
    /// that was gone, so setup could never run again.
    private var stopSharingButton: some View {
        Button(role: .destructive) {
            showingStopSharingConfirmation = true
        } label: {
            HStack(spacing: AppTheme.Spacing.small) {
                if isStoppingSharing {
                    ProgressView().controlSize(.small)
                }
                Label("Stop sharing…", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isStoppingSharing)
        .confirmationDialog(
            "Stop sharing?",
            isPresented: $showingStopSharingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Stop sharing", role: .destructive) {
                Task { await stopSharing() }
            }
        } message: {
            Text("Your assistant will lose access to your students, attendance and school calendar.")
        }
    }

    /// Removes everyone, one run at a time: a second click ran a second removal
    /// against a share the first had just changed, and could say "Couldn't
    /// stop sharing" after it had worked, under an old error that never cleared
    /// (bug hunt 2026-11-02, #40). The members sheet's "Remove everyone…" works
    /// the same way.
    private func stopSharing() async {
        guard let svc = service, !isStoppingSharing else { return }
        isStoppingSharing = true
        defer { isStoppingSharing = false }
        errorMessage = nil
        resultMessage = nil
        do {
            try await svc.removeAllMembers()
            resultMessage = "Everyone else was removed from your classroom. It stays set up, so you can add "
                + "your assistant again later."
        } catch {
            let ns = error as NSError
            Logger.classroomSharing.error(
                "Stop sharing failed: \(ns.domain, privacy: .public) \(ns.code, privacy: .public)"
            )
            errorMessage = AppErrorMessages.sharingMessage(for: error, action: "stop sharing")
            // The share is gone: deleted on another device. Stop showing it here.
            if case ClassroomSharingService.MemberError.noShare = error {
                svc.handleSharingStopped()
            }
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
            resultMessage = report.summary
        } catch {
            let ns = error as NSError
            Logger.classroomSharing.error("""
                Set Up Classroom Sharing failed — \
                domain=\(ns.domain, privacy: .public) \
                code=\(ns.code, privacy: .public) \
                description=\(ns.localizedDescription, privacy: .public)
                """)
            errorMessage = AppErrorMessages.sharingMessage(for: error, action: "set up classroom sharing")
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
            errorMessage = AppErrorMessages.sharingMessage(for: error, action: "open sharing")
        }
    }

    private var assistantActions: some View {
        Button(role: .destructive) {
            showingLeaveConfirmation = true
        } label: {
            Label("Leave classroom", systemImage: "rectangle.portrait.and.arrow.right")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .confirmationDialog(
            "Leave classroom?",
            isPresented: $showingLeaveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Leave", role: .destructive) {
                Task {
                    do {
                        try await service?.leaveClassroom()
                    } catch {
                        errorMessage = AppErrorMessages.sharingMessage(for: error, action: "leave the classroom")
                    }
                }
            }
        } message: {
            Text("Shared classroom data will be removed from this device.")
        }
    }
}
