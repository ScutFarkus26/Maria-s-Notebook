import SwiftUI

// MARK: - Settings Dashboard View

/// Overview: what needs the guide right now, each with a one-tap fix, and a
/// calm "All set" when nothing does. Below it, three small status tiles.
struct SettingsDashboardView: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @TestStudentVisibility private var testStudents
    var statsViewModel: SettingsStatsViewModel
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
        VStack(spacing: SettingsStyle.sectionSpacing) {
            WhatsNewBanner()

            if let model {
                attentionSection(model)
            }

            statusTiles

            SettingsFooterView()
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

    // MARK: - Needs Your Attention

    @ViewBuilder
    private func attentionSection(_ model: SettingsDashboardViewModel) -> some View {
        let items = model.items(syncHealth: syncHealth)
        VStack(spacing: SettingsStyle.groupSpacing) {
            if items.isEmpty {
                allSetCard
            } else {
                SettingsGroup(title: "Needs your attention", systemImage: "exclamationmark.circle") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 {
                                Divider()
                            }
                            attentionRow(item, model: model)
                                .padding(.vertical, AppTheme.Spacing.small)
                        }
                    }
                }
            }

            if model.backupRun == .succeeded {
                Label("Backed up just now. The copy is in your backup folder.", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.success)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .adaptiveAnimation(.easeInOut(duration: 0.25), value: items)
        // A small cheer when the guide's own backup is the notebook's first, or
        // clears the last item; never for a warning that clears by itself.
        .settingsCelebration(
            trigger: model.backupRun == .succeeded && (items.isEmpty || model.madeFirstBackup)
        )
    }

    private var allSetCard: some View {
        HStack(spacing: AppTheme.Spacing.compact) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(AppColors.success)
                .accessibilityHidden(true)
            Text(syncHealth == .healthy
                 ? "All set. Your notebook is backed up and in sync."
                 : "All set. Nothing needs you right now.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func attentionRow(_ item: SettingsAttentionItem, model: SettingsDashboardViewModel) -> some View {
        let text = HStack(alignment: .top, spacing: AppTheme.Spacing.compact) {
            Image(systemName: item.systemImage)
                .font(.title3)
                .foregroundStyle(tint(for: item))
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if case .backupDue = item, case .failed(let message) = model.backupRun {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(AppColors.destructive)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)

        if horizontalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                text
                action(for: item, model: model)
                    .padding(.leading, 28 + AppTheme.Spacing.compact)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .center, spacing: AppTheme.Spacing.compact) {
                text
                Spacer(minLength: AppTheme.Spacing.small)
                action(for: item, model: model)
            }
        }
    }

    @ViewBuilder
    private func action(for item: SettingsAttentionItem, model: SettingsDashboardViewModel) -> some View {
        if let destination = item.destination {
            Button(item.actionTitle) {
                if let focus = item.focus {
                    onOpenCard(focus)
                } else {
                    onOpen(destination)
                }
            }
                .buttonStyle(.bordered)
                .controlSize(.small)
        } else if model.backupRun == .running {
            HStack(spacing: AppTheme.Spacing.small) {
                ProgressView()
                    .controlSize(.small)
                Text("Backing up…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } else {
            Button(item.actionTitle) {
                Task { await model.backUpNow(viewContext: viewContext) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private func tint(for item: SettingsAttentionItem) -> Color {
        switch item {
        case .syncProblem(let isError): return isError ? AppColors.destructive : AppColors.warning
        case .backupDue, .unsharedClassroomRecords, .connectionAccessLost: return AppColors.warning
        case .carriedOverPlans: return AppColors.info
        }
    }

    // MARK: - Status Tiles

    private var statusTiles: some View {
        let columnCount = dynamicTypeSize.isAccessibilitySize ? 1 : 3
        let columns = Array(repeating: GridItem(.flexible(), spacing: AppTheme.Spacing.compact), count: columnCount)
        let aiReady = AIClientRouter.isAvailable
        let templates = statsViewModel.noteTemplatesCount + statsViewModel.meetingTemplatesCount
            + statsViewModel.todoTemplatesCount

        return LazyVGrid(columns: columns, spacing: AppTheme.Spacing.compact) {
            DashboardStatusTile(
                title: "iCloud",
                value: syncStatusText,
                systemImage: syncHealth.icon,
                tint: syncTint,
                syncHealth: syncHealth,
                category: .syncBackup,
                onOpen: onOpen
            )

            DashboardStatusTile(
                title: "Apple Intelligence",
                value: aiReady ? "Ready" : "Not available",
                systemImage: "apple.intelligence",
                tint: aiReady ? Color.accentColor : AppColors.warning,
                category: .intelligence,
                onOpen: onOpen
            )

            DashboardStatusTile(
                title: "Templates",
                value: templates == 1 ? "1 template" : "\(templates) templates",
                systemImage: "doc.on.doc.fill",
                tint: Color.accentColor,
                category: .templates,
                onOpen: onOpen
            )
        }
    }

    private var syncStatusText: String {
        switch syncHealth {
        case .healthy: return "Up to date"
        case .syncing: return "Syncing…"
        case .warning: return "Running behind"
        case .error: return "Needs a look"
        case .offline: return "Offline"
        case .unknown: return "Checking…"
        }
    }

    private var syncTint: Color {
        switch syncHealth {
        case .healthy: return AppColors.success
        case .syncing: return AppColors.info
        case .warning: return AppColors.warning
        case .error: return AppColors.destructive
        case .offline, .unknown: return .secondary
        }
    }
}

// MARK: - Status Tile

/// A small tappable tile: icon, name, one-line status. Opens its category.
private struct DashboardStatusTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
    /// Draws the sky icon for this sync state in place of `systemImage`.
    var syncHealth: CloudKitHealthCheck.SyncHealth?
    let category: SettingsCategory
    let onOpen: (SettingsCategory) -> Void

    var body: some View {
        Button {
            onOpen(category)
        } label: {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
                Group {
                    if let syncHealth {
                        SyncSkyIcon(health: syncHealth)
                    } else {
                        Image(systemName: systemImage)
                            .foregroundStyle(tint)
                    }
                }
                .font(.subheadline)
                .accessibilityHidden(true)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle(padding: SettingsStyle.compactPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(category.displayName)")
    }
}
