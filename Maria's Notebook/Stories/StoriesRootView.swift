import SwiftUI
import CoreData
import UniformTypeIdentifiers
import OSLog

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

    @State private var selectedStoryID: NSManagedObjectID?
    @State var isShowingFileImporter = false
    @State private var isDropTargeted = false
    @State private var importErrorMessage: String?

    nonisolated private static let logger = Logger.stories

    private var filteredStories: [CDStory] {
        viewModel.filter(stories: Array(stories), state: filterState)
    }

    private var selectedStory: CDStory? {
        guard let id = selectedStoryID else { return nil }
        return stories.first { $0.objectID == id }
    }

    var body: some View {
        HStack(spacing: 0) {
            mainColumn
            if let story = selectedStory {
                Divider()
                StoryDetailView(
                    story: story,
                    onClose: { selectedStoryID = nil },
                    onDelete: { selectedStoryID = nil }
                )
                .frame(width: 480)
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedStoryID)
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [UTType.pdf],
            allowsMultipleSelection: true
        ) { result in
            handleFileImporter(result)
        }
        .alert(
            "Couldn't import PDF",
            isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            ),
            presenting: importErrorMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    private var mainColumn: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(dropOverlay)
        .onDrop(of: [UTType.pdf], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    @ViewBuilder
    private var content: some View {
        if filteredStories.isEmpty {
            emptyState
        } else {
            storiesGrid
        }
    }

    private var storiesGrid: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(filteredStories, id: \.objectID) { story in
                    storyCard(for: story)
                }
            }
            .padding(16)
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 16)]
    }

    private func storyCard(for story: CDStory) -> some View {
        let isSelected = story.objectID == selectedStoryID
        return Button {
                selectedStoryID = isSelected ? nil : story.objectID
            } label: {
                StoryCardView(story: story, isSelected: isSelected)
            }
            .buttonStyle(.plain)
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text(stories.isEmpty ? "No stories yet" : "No stories match your filters")
                .font(.title3.weight(.semibold))
            if stories.isEmpty {
                Text("Drag a PDF here, or use Add PDF, to import a story.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
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
            } else {
                Button("Clear filters") {
                    filterState.clearAll()
                }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var dropOverlay: some View {
        if isDropTargeted {
            ZStack {
                Color.accentColor.opacity(0.08)
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.accentColor)
                    Text("Drop PDF to add a story")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: - Drop / Import

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { url, error in
                guard let url else {
                    if let error {
                        Self.logger.warning("Drop failed: \(error.localizedDescription, privacy: .public)")
                    }
                    return
                }
                // The provided URL is in a temp location that gets cleaned up when the
                // closure returns; copy to a stable temp path before hopping main actor.
                let tempCopy = Self.copyToTempIfNeeded(url)
                Task { @MainActor in
                    importPDF(at: tempCopy ?? url)
                }
            }
        }
    }

    nonisolated private static func copyToTempIfNeeded(_ url: URL) -> URL? {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        do {
            try fm.copyItem(at: url, to: temp)
            return temp
        } catch {
            Self.logger.warning("Failed to copy dropped PDF to temp: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func handleFileImporter(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                let didStart = url.startAccessingSecurityScopedResource()
                defer { if didStart { url.stopAccessingSecurityScopedResource() } }
                importPDF(at: url)
            }
        case .failure(let error):
            importErrorMessage = error.localizedDescription
        }
    }

    private func importPDF(at url: URL) {
        do {
            try StoryImportService.importPDF(at: url, context: viewContext)
        } catch let error as StoryImportService.ImportRejection {
            importErrorMessage = error.errorDescription
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }
}
