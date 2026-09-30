import SwiftUI
import CoreData

// MARK: - SettingsView

struct SettingsView: View {
    private let showsPageHeader: Bool
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies
    @State var statsViewModel = SettingsStatsViewModel()
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    /// A card the Overview opened (wide layout); cleared once another category is picked.
    @State private var requestedFocus: SettingsCopy.Group?
    @State private var searchText = ""
    /// The iPhone's pushed panes, so the Overview can open another category.
    @State private var compactPath: [SettingsPaneRoute] = []
    @AppStorage(UserDefaultsKeys.settingsSelectedCategory) private var selectedCategoryRaw: String = ""

    init(showsPageHeader: Bool = true) {
        self.showsPageHeader = showsPageHeader
    }

    var isCompact: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }

    /// The open category; a selection saved by an older build maps onto the new categories.
    var selectedCategory: SettingsCategory {
        SettingsCategory(storedValue: selectedCategoryRaw) ?? .overview
    }

    var selectedCategoryBinding: Binding<SettingsCategory?> {
        Binding<SettingsCategory?>(
            get: { selectedCategory },
            set: { selectedCategoryRaw = ($0 ?? .overview).rawValue }
        )
    }

    var filteredCategories: [SettingsCategory] {
        SettingsCategory.visibleCategories.filter { $0.matches(searchText) }
    }

    private func categories(in section: SettingsCategory.Section) -> [SettingsCategory] {
        filteredCategories.filter { $0.section == section }
    }

    private var isSearching: Bool { SettingsSearch.isSearching(searchText) }

    /// A search that matches nothing at all.
    private var hasNoResults: Bool { isSearching && filteredCategories.isEmpty }

    /// The card the wide layout scrolls to and outlines: the open category's
    /// first card that matches the search.
    private var searchFocus: SettingsCopy.Group? {
        SettingsSearch.firstMatchingGroup(in: selectedCategory, query: searchText)
    }

    /// The wide layout's card to show: a search match, else a card the Overview asked for.
    private var paneFocus: SettingsCopy.Group? {
        searchFocus ?? requestedFocus.flatMap { $0.category == selectedCategory ? $0 : nil }
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sidebarWidth: CGFloat {
        #if os(macOS)
        return 240
        #else
        return horizontalSizeClass == .regular ? 260 : 200
        #endif
    }

    /// Opens a category from inside a pane (the Overview's fix buttons): selects
    /// it beside the sidebar, or pushes its pane on iPhone.
    func openCategory(_ category: SettingsCategory) {
        if isCompact {
            compactPath.append(SettingsPaneRoute(category: category))
        } else {
            selectedCategoryRaw = category.rawValue
        }
    }

    /// Opens the category that holds a card, scrolled to the card and outlined.
    func openCard(_ group: SettingsCopy.Group) {
        if isCompact {
            compactPath.append(SettingsPaneRoute(category: group.category, focus: group))
        } else {
            requestedFocus = group
            selectedCategoryRaw = group.category.rawValue
        }
    }

    var body: some View {
        NavigationStack(path: $compactPath) {
            VStack(spacing: 0) {
                if showsPageHeader {
                    ViewHeader(title: "Settings")
                    Divider()
                }
                settingsContent
            }
        }
        .inlineNavigationTitle()
        .onChange(of: selectedCategoryRaw) { _, _ in
            // A card the Overview asked for belongs to that one visit.
            if requestedFocus?.category != selectedCategory { requestedFocus = nil }
        }
        .onChange(of: isCompact) { _, compact in
            // The pushed panes belong to the iPhone list; the wide layout has none.
            if !compact { compactPath.removeAll() }
        }
        .onDisappear { statsViewModel.stopObserving() }
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
            SettingsSidebarSearchField(text: $searchText)
                .padding(.horizontal, AppTheme.Spacing.compact)
                .padding(.top, AppTheme.Spacing.compact)
                .padding(.bottom, AppTheme.Spacing.small)

            List(selection: selectedCategoryBinding) {
                ForEach(SettingsCategory.Section.allCases, id: \.self) { section in
                    let sectionCategories = categories(in: section)
                    if !sectionCategories.isEmpty {
                        Section {
                            ForEach(sectionCategories) { category in
                                categoryRow(category)
                                    .tag(category)
                            }
                        } header: {
                            if let title = section.title {
                                Text(title)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .overlay(alignment: .top) {
                if hasNoResults {
                    Text("No settings match “\(trimmedSearchText)”")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppTheme.Spacing.compact)
                        .padding(.top, AppTheme.Spacing.large)
                }
            }
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
        case .syncBackup:
            SyncSkyIcon(health: dependencies.cloudKitSyncStatusService.syncHealth)
                .font(.caption)
        case .intelligence:
            Circle()
                .fill(AIClientRouter.isAvailable ? AppColors.success : AppColors.warning)
                .frame(width: 8, height: 8)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var settingsDetailPane: some View {
        if hasNoResults {
            ContentUnavailableView.search(text: trimmedSearchText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // While searching, scrolls to the open category's first matching card.
            SettingsPaneScrollView(focus: paneFocus?.anchorID) {
                VStack(alignment: .leading, spacing: SettingsStyle.groupSpacing) {
                    SettingsCategoryHeader(category: selectedCategory)
                    settingsPaneContent(for: selectedCategory)
                }
                .frame(maxWidth: 700)
                .padding(.horizontal, AppTheme.Spacing.large)
                .padding(.vertical, AppTheme.Spacing.medium)
                .frame(maxWidth: .infinity)
                .transition(.opacity)
                .id(selectedCategoryRaw)
            }
            .animation(.easeInOut(duration: 0.2), value: selectedCategoryRaw)
        }
    }

    // MARK: - Compact Layout (iPhone)

    private var compactSettingsList: some View {
        List {
            ForEach(SettingsCategory.Section.allCases, id: \.self) { section in
                let sectionCategories = categories(in: section)
                if !sectionCategories.isEmpty {
                    Section {
                        ForEach(sectionCategories) { category in
                            NavigationLink(value: SettingsPaneRoute(category: category)) {
                                categoryRow(category)
                            }
                            // While searching, the matching cards, each opening its pane at that card.
                            ForEach(SettingsSearch.matchingGroups(in: category, query: searchText)) { group in
                                NavigationLink(value: SettingsPaneRoute(category: category, focus: group)) {
                                    SettingsSearchResultRow(group: group)
                                }
                            }
                        }
                    } header: {
                        if let title = section.title {
                            Text(title)
                        }
                    }
                }
            }
        }
        .overlay {
            if hasNoResults {
                ContentUnavailableView.search(text: trimmedSearchText)
            }
        }
        .searchable(text: $searchText, prompt: "Search settings")
        .navigationDestination(for: SettingsPaneRoute.self) { route in
            SettingsPaneScrollView(focus: route.focus?.anchorID) {
                settingsPaneContent(for: route.category)
                    .padding(.horizontal, AppTheme.Spacing.medium)
                    .padding(.vertical, AppTheme.Spacing.compact)
            }
            .navigationTitle(route.category.displayName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
        }
    }

    // MARK: - Category Row

    private func categoryRow(_ category: SettingsCategory) -> some View {
        HStack(spacing: 10) {
            SettingsCategoryIcon(category: category)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                Text(category.displayName)
                Text(category.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            connectionStatusDot(for: category)
        }
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct SettingsViewPreview: View {
    var body: some View {
        SettingsView()
    }
}

#Preview {
    SettingsViewPreview()
}
