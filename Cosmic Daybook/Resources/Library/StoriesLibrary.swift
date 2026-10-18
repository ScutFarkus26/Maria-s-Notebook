import SwiftUI
import CoreData

/// Resources › Stories: story PDFs with their covers, grade bands and themes,
/// read by Apple Intelligence when it's on.
struct StoriesLibrary: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDStory.createdAt, ascending: false)],
        animation: .default
    )
    private var stories: FetchedResults<CDStory>

    @State private var filterState = StoriesFilterState()
    private let viewModel = StoriesViewModel()
    private let importQueue = StoryImportQueue.shared

    @State private var isShowingFileImporter = false

    var body: some View {
        let allStories = Array(stories)
        PDFLibraryListView(
            items: allStories,
            sections: [PDFLibrarySection(title: nil, items: viewModel.filter(stories: allStories, state: filterState))],
            isShowingFileImporter: $isShowingFileImporter,
            dropPrompt: "Drop PDF to add a story",
            logger: .stories,
            importPDF: { url in
                do {
                    try LibraryImportService.importStory(at: url, context: viewContext)
                    return nil
                } catch {
                    return LibraryImportService.message(for: error)
                }
            },
            header: { headerBar },
            card: { story, isSelected in
                StoryCardView(story: story, isSelected: isSelected)
            },
            detail: { story, dismiss in
                StoryDetailView(story: story, onClose: dismiss, onDelete: dismiss)
            },
            emptyState: { emptyState }
        )
    }

    private var headerBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                LibrarySearchField(prompt: "Search stories", text: $filterState.searchText)
                if filterState.hasActiveFilters {
                    Button("Clear") {
                        filterState.clearAll()
                    }
                    .buttonStyle(.borderless)
                }
                Spacer(minLength: 0)
                if importQueue.pendingCount > 0 {
                    Label(
                        "Analyzing \(importQueue.completedInBatch + 1) of \(importQueue.batchSize)…",
                        systemImage: "wand.and.stars"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Button {
                    isShowingFileImporter = true
                } label: {
                    Label("Add Story", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            filterChipBar
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var filterChipBar: some View {
        let themesUniverse = viewModel.themesUniverse(from: Array(stories))
        if !themesUniverse.isEmpty || !StoryGradeBand.filterBuckets.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(StoryGradeBand.filterBuckets, id: \.self) { band in
                        let isSelected = filterState.selectedGradeBand == band
                        StoryThemeChip(
                            band.displayName,
                            variant: .selectable(isSelected: isSelected) {
                                filterState.selectedGradeBand = isSelected ? nil : band
                            }
                        )
                    }
                    if !themesUniverse.isEmpty {
                        Divider().frame(height: 16)
                    }
                    ForEach(themesUniverse, id: \.self) { theme in
                        let isSelected = filterState.selectedThemes.contains(theme)
                        StoryThemeChip(
                            theme,
                            variant: .selectable(isSelected: isSelected) {
                                if isSelected {
                                    filterState.selectedThemes.remove(theme)
                                } else {
                                    filterState.selectedThemes.insert(theme)
                                }
                            }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var emptyState: some View {
        PDFLibraryEmptyState(
            systemImage: "books.vertical",
            isLibraryEmpty: stories.isEmpty,
            emptyTitle: "No stories yet",
            filteredTitle: "No stories match your filters",
            hint: PlatformIdiom.isPhone
                ? "Use Add Story to import a story PDF."
                : "Drag a PDF here, or use Add Story, to import a story.",
            clearFilters: { filterState.clearAll() },
            footer: {
                if !StoryAnalyzer.isAIEnabled {
                    Text(
                        "Apple Intelligence isn't available " +
                        "— you'll fill in titles, themes, and grade levels by hand."
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
        )
    }
}
