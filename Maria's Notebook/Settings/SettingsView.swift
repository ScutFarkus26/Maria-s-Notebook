import SwiftUI
import CoreData
import UniformTypeIdentifiers

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies
    @State var statsViewModel = SettingsStatsViewModel()
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var searchText = ""
    @AppStorage("settings_selectedCategory") private var selectedCategoryRaw: String = ""

    var isCompact: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }

    var selectedCategory: SettingsCategory? {
        SettingsCategory(rawValue: selectedCategoryRaw)
    }

    var selectedCategoryBinding: Binding<SettingsCategory?> {
        Binding<SettingsCategory?>(
            get: { SettingsCategory(rawValue: selectedCategoryRaw) },
            set: { selectedCategoryRaw = $0?.rawValue ?? "" }
        )
    }

    var filteredCategories: [SettingsCategory] {
        let visible = SettingsCategory.visibleCategories
        guard !searchText.isEmpty else { return visible }
        let query = searchText.lowercased()
        return visible.filter {
            $0.searchKeywords.lowercased().contains(query) ||
            $0.displayName.lowercased().contains(query) ||
            $0.detailedSettings.contains { $0.lowercased().contains(query) }
        }
    }

    private var sidebarWidth: CGFloat {
        #if os(macOS)
        return 240
        #else
        return horizontalSizeClass == .regular ? 260 : 200
        #endif
    }

    var overviewColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        let columnCount = horizontalSizeClass == .regular ? 4 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 16), count: columnCount)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ViewHeader(title: "Settings")
                Divider()
                settingsContent
            }
        }
        .inlineNavigationTitle()
        .fileImporter(
            isPresented: $showingSettingsImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            do {
                if let url = try result.get().first {
                    let data = try Data(contentsOf: url)
                    try SettingsExportService.importSettings(from: data)
                    settingsImportMessage = "Settings imported successfully"
                }
            } catch {
                settingsImportMessage = "Import failed: \(error.localizedDescription)"
            }
        }
        .alert("Settings Import", isPresented: Binding(
            get: { settingsImportMessage != nil },
            set: { if !$0 { settingsImportMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            if let msg = settingsImportMessage {
                Text(msg)
            }
        }
        .onAppear {
            statsViewModel.loadCounts(context: viewContext)

            if !UserDefaults.standard.bool(forKey: UserDefaultsKeys.ephemeralSessionFlag) {
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastStoreErrorDescription)
            }
        }
    }

    // MARK: - Layout Switching

    @ViewBuilder
    private var settingsContent: some View {
        if isCompact {
            compactSettingsList
        } else {
            wideSettingsLayout
        }
    }

    // MARK: - Wide Layout (Mac / iPad)

    private var wideSettingsLayout: some View {
        HStack(spacing: 0) {
            settingsSidebar
                .frame(width: sidebarWidth)
            Divider()
            settingsDetailPane
        }
    }

    private var settingsSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(UIConstants.OpacityConstants.trace))
            )
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            List(filteredCategories, selection: selectedCategoryBinding) { category in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(category.displayName, systemImage: category.icon)
                        Text(category.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    connectionStatusDot(for: category)
                    if category.wasRecentlyModified {
                        Circle()
                            .fill(AppColors.info)
                            .frame(width: 6, height: 6)
                    }
                }
                .tag(category)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .background(SettingsStyle.groupBackgroundColor.opacity(UIConstants.OpacityConstants.half))
        .onChange(of: searchText) { _, _ in
            let filtered = filteredCategories
            if filtered.count == 1, let match = filtered.first {
                selectedCategoryRaw = match.rawValue
            }
        }
    }

    // MARK: - Connection Status Dots

    @ViewBuilder
    private func connectionStatusDot(for category: SettingsCategory) -> some View {
        switch category {
        case .dataSync:
            Circle()
                .fill(syncHealthColor(dependencies.cloudKitSyncStatusService.syncHealth))
                .frame(width: 8, height: 8)
        case .aiFeatures:
            Circle()
                .fill(AnthropicAPIClient.hasAPIKey() ? AppColors.success : AppColors.warning)
                .frame(width: 8, height: 8)
        default:
            EmptyView()
        }
    }

    private func syncHealthColor(_ health: CloudKitHealthCheck.SyncHealth) -> Color {
        switch health {
        case .healthy: return AppColors.success
        case .syncing: return AppColors.info
        case .warning: return AppColors.warning
        case .error: return AppColors.destructive
        case .offline, .unknown: return .gray
        }
    }

    private var settingsDetailPane: some View {
        ScrollView {
            Group {
                if let category = selectedCategory {
                    settingsPaneContent(for: category)
                } else {
                    SettingsDashboardView(statsViewModel: statsViewModel)
                }
            }
            .frame(maxWidth: 700)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .transition(.opacity)
            .id(selectedCategoryRaw)
        }
        .animation(.easeInOut(duration: 0.2), value: selectedCategoryRaw)
    }

    // MARK: - Compact Layout (iPhone)

    private var compactSettingsList: some View {
        List {
            ForEach(filteredCategories) { category in
                NavigationLink(value: category) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(category.displayName, systemImage: category.icon)
                            Text(category.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                        connectionStatusDot(for: category)
                        if category.wasRecentlyModified {
                            Circle()
                                .fill(AppColors.info)
                                .frame(width: 6, height: 6)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search settings")
        .navigationDestination(for: SettingsCategory.self) { category in
            ScrollView {
                settingsPaneContent(for: category)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .navigationTitle(category.displayName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
        }
    }

    // iCloud Backup Toggle
    @AppStorage(UserDefaultsKeys.cloudBackupScheduleEnabled) var cloudBackupEnabled = false

    // Settings Import
    @State var showingSettingsImporter = false
    @State var settingsImportMessage: String?
}

// MARK: - Apple Intelligence Status Row

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, iOS 26.0, *)
struct AppleIntelligenceStatusRow: View {
    private let client = LocalModelClient()

    var body: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Image(systemName: client.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(client.isAvailable ? AppColors.success : AppColors.warning)
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 2) {
                Text(client.isAvailable ? "Available" : "Not Available")
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(client.isAvailable ? AppColors.success : AppColors.warning)

                if !client.isAvailable {
                    Text(client.unavailabilityReason)
                        .font(AppTheme.ScaledFont.captionSmall)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}
#endif

#Preview {
    SettingsView()
}
