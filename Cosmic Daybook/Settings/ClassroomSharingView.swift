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
    #if os(macOS)
    @State private var showingStopSharingConfirmation = false
    #endif
    @State private var showingSetupConfirmation = false
    @State private var errorMessage: String?
    @State private var resultMessage: String?
    @State private var isPreparingShare = false
    @State private var isSettingUp = false
    @State private var contents: ClassroomShareContents?

    private var service: ClassroomSharingService? { sharingService }

    var body: some View {
        VStack(spacing: SettingsStyle.groupSpacing) {
            shareStatusCard
            roleGroup
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
                        message: "Set up classroom sharing once, on one of your devices, to give an assistant " +
                            "your class list, attendance and school calendar."
                    )
                }
            } else if let contents {
                if contents.outside > 0 {
                    ClassroomShareBanner(
                        icon: "exclamationmark.triangle.fill",
                        tint: AppColors.warning,
                        title: Self.outsideTitle(contents.outside),
                        message: "Your assistant can't see them. The share holds \(contents.summary)."
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
            ? "1 classroom record isn't in the classroom share"
            : "\(count.formatted()) classroom records aren't in the classroom share"
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
            if service?.isSharing == true {
                manageSharingButton
                if (contents?.outside ?? 0) > 0 {
                    setUpButton(title: "Add them to the share", prominent: false)
                }
                stopSharingButton
            } else {
                setUpButton(title: "Set up classroom sharing", prominent: true)
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
                ClassroomSharingSheet(service: svc, contents: contents) {
                    showingSharingSheet = false
                    try? svc.refreshParticipants()
                }
            }
        }
    }

    /// On the Mac this removes everyone, so it asks first. On iPad and iPhone
    /// it opens the system sharing sheet, whose own Stop Sharing asks — a
    /// dialog here as well would make the guide confirm twice.
    private var stopSharingButton: some View {
        Button(role: .destructive) {
            #if os(macOS)
            showingStopSharingConfirmation = true
            #else
            showingSharingSheet = true
            #endif
        } label: {
            Label("Stop sharing…", systemImage: "xmark.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        #if os(macOS)
        .confirmationDialog(
            "Stop sharing?",
            isPresented: $showingStopSharingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Stop sharing", role: .destructive) {
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
            }
        } message: {
            Text("Your assistant will lose access to your students, attendance and school calendar.")
        }
        #endif
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
            message += report.attached == 1 ? "1 record added." : "\(report.attached.formatted()) records added."
            if let contents = report.contents { message += " The share holds \(contents.summary)." }
            if report.failed > 0 {
                message += " \(report.failed.formatted()) couldn't be added"
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
                        errorMessage = AppErrorMessages.userMessage(for: error, context: "leaving the classroom")
                    }
                }
            }
        } message: {
            Text("Shared classroom data will be removed from this device.")
        }
    }
}
