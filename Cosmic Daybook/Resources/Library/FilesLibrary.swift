import SwiftUI
import CoreData

/// Resources › Files: the guide's own documents (writing papers, printables,
/// guides, forms), any file type, by category, with tags, favorites and links
/// to lessons and areas. Extensions: `+Header` (filters, select bar),
/// `+Actions` (changes, bulk actions, sheets).
struct FilesLibrary: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.dependencies) var dependencies

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDResource.createdAt, ascending: false)])
    var allResourcesRaw: FetchedResults<CDResource>

    @State var searchText = ""
    @State var selectedCategory: ResourceCategory?
    @State var smartFilter: ResourceSmartFilter = .all
    @State var selectedTagFilter: String?
    @State var isShowingImportSheet = false

    // Select mode
    @State var isSelectMode = false
    @State var selectedObjectIDs: Set<NSManagedObjectID> = []
    @State var isShowingBulkCategoryPicker = false
    @State var isShowingBulkTagPicker = false
    @State var isShowingBulkDeleteConfirmation = false
    @State var bulkTags: [String] = []

    // Rename / change category
    @State var resourceToRename: CDResource?
    @State var renameText = ""
    @State var resourceToRecategorize: CDResource?

    /// One row per logical resource.
    ///
    /// Resources are assigned to both store configurations, and the shared →
    /// private clone kept each row's `id`, so one resource can come back two or
    /// three times from an unscoped fetch until the launch-time cleanup folds
    /// the copies away.
    var allResources: [CDResource] { Array(allResourcesRaw).uniqueByID }

    var filteredResources: [CDResource] {
        ResourceLibraryFilter(
            smartFilter: smartFilter,
            category: selectedCategory,
            tag: selectedTagFilter,
            searchText: searchText
        ).apply(to: allResources)
    }

    /// True if any filter beyond "All" is active.
    var hasActiveFilter: Bool {
        selectedCategory != nil || smartFilter != .all || selectedTagFilter != nil || !searchText.isEmpty
    }

    /// Grouped by category while nothing is filtered; one run otherwise.
    var sections: [PDFLibrarySection<CDResource>] {
        let shown = filteredResources
        guard !hasActiveFilter else { return [PDFLibrarySection(title: nil, items: shown)] }
        let grouped = Dictionary(grouping: shown, by: \.category)
        return ResourceCategory.allCases.compactMap { category in
            guard let resources = grouped[category], !resources.isEmpty else { return nil }
            return PDFLibrarySection(title: category.rawValue, systemImage: category.icon, items: resources)
        }
    }

    /// What select mode acts on (`ResourceSelection`).
    var resourceSelection: ResourceSelection<NSManagedObjectID> {
        ResourceSelection(visibleIDs: filteredResources.map(\.objectID), selectedIDs: selectedObjectIDs)
    }

    /// How many ticked resources the filter shows: the "N selected" count.
    var selectedCount: Int { resourceSelection.actedOnIDs.count }

    /// The ticked resources the filter shows: what the bulk actions change.
    var selectedResources: [CDResource] {
        let acted = resourceSelection.actedOnIDs
        return filteredResources.filter { acted.contains($0.objectID) }
    }

    var body: some View {
        attachSheets(to: list)
    }

    private var list: some View {
        PDFLibraryListView(
            items: allResources,
            sections: sections,
            dropPrompt: "Drop PDF files to add them",
            logger: .resources,
            importPDF: { url in
                LibraryImportService.importDroppedResource(
                    at: url, context: viewContext, saveCoordinator: dependencies.saveCoordinator
                )
            },
            multiSelection: isSelectMode ? $selectedObjectIDs : nil,
            header: { headerBar },
            card: { resource, isSelected in
                ResourceCard(resource: resource, isSelected: isSelected)
                    .contextMenu {
                        if !isSelectMode {
                            cardMenu(for: resource)
                        }
                    }
            },
            detail: { resource, close in
                ResourceDetailView(resource: resource, onClose: close)
            },
            emptyState: { emptyState }
        )
    }

    private var emptyState: some View {
        PDFLibraryEmptyState(
            systemImage: "tray.2",
            isLibraryEmpty: allResources.isEmpty,
            emptyTitle: "No files yet",
            filteredTitle: "No files match your filters",
            hint: PlatformIdiom.isPhone
                ? "Use Add File to keep writing papers, templates, guides and more here."
                : "Drag a PDF here, or use Add File, to keep writing papers, templates, guides and more here.",
            clearFilters: clearFilters,
            footer: { EmptyView() }
        )
    }

    func clearFilters() {
        searchText = ""
        selectedCategory = nil
        smartFilter = .all
        selectedTagFilter = nil
    }
}

// MARK: - Filtering

/// Favorites and Recents, the library's quick views.
enum ResourceSmartFilter: String {
    case all
    case favorites
    case recents

    var displayName: String {
        switch self {
        case .all: return "All"
        case .favorites: return "Favorites"
        case .recents: return "Recents"
        }
    }
}

/// The Files list's filters, applied in the order the library always used:
/// quick view, then category, tag and search.
struct ResourceLibraryFilter {
    var smartFilter: ResourceSmartFilter = .all
    var category: ResourceCategory?
    var tag: String?
    var searchText = ""

    /// How many recently opened files Recents shows.
    static let recentsLimit = 20

    func apply(to resources: [CDResource]) -> [CDResource] {
        var result: [CDResource]
        switch smartFilter {
        case .all:
            result = resources
        case .favorites:
            result = resources.filter(\.isFavorite)
        case .recents:
            result = Array(resources
                .filter { $0.lastViewedAt != nil }
                .sorted { ($0.lastViewedAt ?? .distantPast) > ($1.lastViewedAt ?? .distantPast) }
                .prefix(Self.recentsLimit))
        }

        if let category {
            result = result.filter { $0.category == category }
        }

        if let tag {
            let tagName = TagHelper.tagName(tag).lowercased()
            result = result.filter { resource in
                resource.tagsArray.contains { TagHelper.tagName($0).lowercased() == tagName }
            }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(query) ||
                $0.descriptionText.lowercased().contains(query) ||
                $0.categoryRaw.lowercased().contains(query) ||
                $0.tagsArray.contains { $0.lowercased().contains(query) }
            }
        }
        return result
    }
}
