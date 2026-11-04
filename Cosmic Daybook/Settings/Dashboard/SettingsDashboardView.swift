import SwiftUI

// MARK: - Settings Status Section

/// The top of the Settings list (what the Overview pane became, 2026-11-03):
/// What's New while there's something new, one status row, and a row for
/// each thing that needs the guide, each opening its fix or, for a backup,
/// running it in place.
struct SettingsDashboardView: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.scenePhase) private var scenePhase
    @TestStudentVisibility private var testStudents
    /// Opens another category: selects it beside the sidebar, or pushes its pane on iPhone.
    var onOpen: (SettingsCategory) -> Void
    /// Opens the category that holds a card, scrolled to that card and outlined.
    var onOpenCard: (SettingsCopy.Group) -> Void

    /// Nil until the first reads finish, so the list never flashes "All set"
    /// or "No backup yet" before it knows.
    @State private var model: SettingsDashboardViewModel?
    @State private var carriedOverRefresh: Task<Void, Never>?

    private var syncHealth: CloudKitHealthCheck.SyncHealth {
        dependencies.cloudKitSyncStatusService.syncHealth
    }

    var body: some View {
        Section {
            WhatsNewBanner()

            if let model {
                let items = model.items(syncHealth: syncHealth)
                statusRow(itemCount: items.count)
                ForEach(items) { item in
                    attentionRow(item, model: model)
                }
                if case .succeeded(let partial) = model.backupRun {
                    Label(
                        SettingsDashboardViewModel.succeededText(partial: partial),
                        systemImage: partial ? "info.circle.fill" : "checkmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(partial ? AppColors.warning : AppColors.success)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .task { await load() }
        .onChange(of: scenePhase) { _, phase in
            // Access may have been changed in Settings, or a backup written on quit.
            guard phase == .active, let model else { return }
            model.refreshLastBackup()
            model.refreshConnections()
        }
        .onPresentationDataChange(of: ["Student"], in: viewContext) { _ in
            refreshCarriedOverSoon()
        }
        .onDisappear { carriedOverRefresh?.cancel() }
    }

    // MARK: - Loading

    private func load() async {
        let model = self.model ?? SettingsDashboardViewModel(dependencies: dependencies)
        model.refreshLastBackup()
        model.refreshConnections()
        model.refreshCarriedOverPlans(
            context: viewContext,
            showTestStudents: testStudents.show,
            testStudentNames: testStudents.namesRaw
        )
        self.model = model
        await model.refreshUnsharedClassroomRecords()
    }

    /// Recounts carried-over plans once a burst of roster changes settles:
    /// the count is a fetch per enrolled child.
    private func refreshCarriedOverSoon() {
        carriedOverRefresh?.cancel()
        carriedOverRefresh = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let model else { return }
            model.refreshCarriedOverPlans(
                context: viewContext,
                showTestStudents: testStudents.show,
                testStudentNames: testStudents.namesRaw
            )
        }
    }

    // MARK: - Rows

    /// iCloud's sky and one line: all set, or how many rows follow.
    private func statusRow(itemCount: Int) -> some View {
        Label {
            Text(Self.statusText(itemCount: itemCount, syncHealth: syncHealth))
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            SyncSkyIcon(health: syncHealth)
        }
        .accessibilityElement(children: .combine)
    }

    /// The status row's line.
    static func statusText(itemCount: Int, syncHealth: CloudKitHealthCheck.SyncHealth) -> String {
        switch itemCount {
        case 0:
            return syncHealth == .healthy
                ? "All set. Your notebook is backed up and in sync."
                : "All set. Nothing needs you right now."
        case 1:
            return "1 thing needs you"
        default:
            return "\(itemCount) things need you"
        }
    }

    @ViewBuilder
    private func attentionRow(_ item: SettingsAttentionItem, model: SettingsDashboardViewModel) -> some View {
        let running = item.destination == nil && model.backupRun == .running
        Button {
            if let focus = item.focus {
                onOpenCard(focus)
            } else if let destination = item.destination {
                onOpen(destination)
            } else {
                Task { await model.backUpNow(viewContext: viewContext) }
            }
        } label: {
            HStack(alignment: .top, spacing: AppTheme.Spacing.small) {
                Image(systemName: item.systemImage)
                    .foregroundStyle(tint(for: item))
                    .frame(width: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                    Text(item.title)
                        .font(.subheadline)
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if case .backupDue = item, case .failed(let message) = model.backupRun {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(AppColors.destructive)
                    }
                    if running {
                        HStack(spacing: AppTheme.Spacing.small) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Backing up…")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Text(item.actionTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(running)
        .accessibilityElement(children: .combine)
    }

    private func tint(for item: SettingsAttentionItem) -> Color {
        switch item {
        case .syncProblem(let isError): return isError ? AppColors.destructive : AppColors.warning
        case .backupDue, .unsharedClassroomRecords, .connectionAccessLost: return AppColors.warning
        case .carriedOverPlans: return AppColors.info
        }
    }
}
