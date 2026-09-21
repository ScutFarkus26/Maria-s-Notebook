import SwiftUI
import CoreData

struct StoriesRootView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDStory.createdAt, ascending: false)],
        animation: .default
    )
    var stories: FetchedResults<CDStory>

    @State var filterState = StoriesFilterState()
    let viewModel = StoriesViewModel()
    let importQueue = StoryImportQueue.shared

    @State var isShowingFileImporter = false

    var body: some View {
        let allStories = Array(stories)
        PDFLibraryListView(
            items: allStories,
            filteredItems: viewModel.filter(stories: allStories, state: filterState),
            isShowingFileImporter: $isShowingFileImporter,
            dropPrompt: "Drop PDF to add a story",
            logger: .stories,
            importPDF: { importPDF(at: $0) },
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

    private var emptyState: some View {
        PDFLibraryEmptyState(
            systemImage: "books.vertical",
            isLibraryEmpty: stories.isEmpty,
            emptyTitle: "No stories yet",
            filteredTitle: "No stories match your filters",
            hint: "Drag a PDF here, or use Add PDF, to import a story.",
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

    /// Returns the alert message when the import fails, `nil` on success.
    private func importPDF(at url: URL) -> String? {
        do {
            try StoryImportService.importPDF(at: url, context: viewContext)
            return nil
        } catch let error as StoryImportService.ImportRejection {
            return error.errorDescription
        } catch {
            return error.localizedDescription
        }
    }
}
