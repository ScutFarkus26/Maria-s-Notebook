import SwiftUI
import SwiftData

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State var statsViewModel = SettingsStatsViewModel()
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var searchText = ""
    @AppStorage("settings_selectedCategory") private var selectedCategoryRaw: String = SettingsCategory.general.rawValue

    var isCompact: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }

    var selectedCategory: SettingsCategory {
        SettingsCategory(rawValue: selectedCategoryRaw) ?? .general
    }

    var selectedCategoryBinding: Binding<SettingsCategory?> {
        Binding<SettingsCategory?>(
            get: { SettingsCategory(rawValue: selectedCategoryRaw) ?? .general },
            set: { if let cat = $0 { selectedCategoryRaw = cat.rawValue } }
        )
    }

    var filteredCategories: [SettingsCategory] {
        let visible = SettingsCategory.visibleCategories
        guard !searchText.isEmpty else { return visible }
        let query = searchText.lowercased()
        return visible.filter {
            $0.searchKeywords.lowercased().contains(query) ||
            $0.displayName.lowercased().contains(query)
        }
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
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            statsViewModel.loadCounts(context: modelContext)

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
                .frame(width: 200)
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
                    .fill(Color.primary.opacity(0.04))
            )
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            List(filteredCategories, selection: selectedCategoryBinding) { category in
                Label(category.displayName, systemImage: category.icon)
                    .tag(category)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .background(SettingsStyle.groupBackgroundColor.opacity(0.5))
    }

    private var settingsDetailPane: some View {
        ScrollView {
            settingsPaneContent(for: selectedCategory)
                .frame(maxWidth: 700)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
        }
        .id(selectedCategory) // Reset scroll position when switching categories
    }

    // MARK: - Compact Layout (iPhone)

    private var compactSettingsList: some View {
        List {
            ForEach(filteredCategories) { category in
                NavigationLink(value: category) {
                    Label(category.displayName, systemImage: category.icon)
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
