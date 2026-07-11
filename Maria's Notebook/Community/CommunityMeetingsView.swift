import SwiftUI
import CoreData

struct CommunityMeetingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(SaveCoordinator.self) private var saveCoordinator
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    @FetchRequest(fetchRequest: {
        let request = NSFetchRequest<CDCommunityTopicEntity>(entityName: "CommunityTopic")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDCommunityTopicEntity.createdAt, ascending: false)]
        request.fetchBatchSize = 50
        // Prefetch proposedSolutions so each TopicRowView's solution count — and
        // the search filter below, which reads proposedSolutions per topic —
        // resolves from the row cache in one batched query instead of faulting
        // the relationship per row (N+1).
        request.relationshipKeyPathsForPrefetching = ["proposedSolutions"]
        return request
    }())
    private var topics: FetchedResults<CDCommunityTopicEntity>

    @State private var showingAdd = false
    @State private var selectedTopic: CDCommunityTopicEntity?

    enum DateFilter { case today, thisWeek, thisMonth, last30, thisYear }
    @State private var filterDate: DateFilter?
    @State private var selectedTag: String?
    @State private var searchText: String = ""

    private var openTopics: [CDCommunityTopicEntity] { topics.filter { !$0.isResolved } }
    private var resolvedTopics: [CDCommunityTopicEntity] { topics.filter(\.isResolved) }

    private var allTags: [String] {
        let raw = topics.flatMap { $0.tags }
        let trimmed = raw.map { $0.trimmed() }
        let filtered = trimmed.filter { !$0.isEmpty }
        return Array(Set(filtered)).sorted()
    }

    private func passesDateFilter(_ t: CDCommunityTopicEntity) -> Bool {
        guard let f = filterDate else { return true }
        guard let createdAt = t.createdAt else { return false }
        let cal = Calendar.current
        let now = Date()
        switch f {
        case .today:
            return cal.isDate(createdAt, inSameDayAs: now)
        case .thisWeek:
            return cal.isDate(createdAt, equalTo: now, toGranularity: .weekOfYear)
        case .thisMonth:
            return cal.isDate(createdAt, equalTo: now, toGranularity: .month)
        case .last30:
            return createdAt >= cal.date(byAdding: .day, value: -30, to: now)!
        case .thisYear:
            return cal.isDate(createdAt, equalTo: now, toGranularity: .year)
        }
    }

    private func matchesSearch(_ t: CDCommunityTopicEntity) -> Bool {
        let q = searchText.trimmed()
        if q.isEmpty { return true }
        let qLower = q.lowercased()

        let baseParts = [t.title, t.issueDescription, t.resolution]
        let baseText = baseParts.joined(separator: "\n")

        let solutionsText = ((t.proposedSolutions?.allObjects as? [CDProposedSolutionEntity]) ?? []).map { part in
            let title = part.title
            let details = part.details
            return "\(title)\n\(details)"
        }.joined(separator: "\n")

        let notesText = t.unifiedNotes.map { note in
            let speaker = note.reporterName ?? ""
            let content = note.body
            return "\(speaker)\n\(content)"
        }.joined(separator: "\n")

        var pieces: [String] = []
        pieces.append(baseText)
        pieces.append(solutionsText)
        pieces.append(notesText)
        let combinedLower: String = pieces.joined(separator: "\n").lowercased()
        return combinedLower.contains(qLower)
    }

    private var filteredOpenTopics: [CDCommunityTopicEntity] {
        let tag = selectedTag?.lowercased()
        return openTopics.filter { t in
            let dateOK = passesDateFilter(t)
            let searchOK = matchesSearch(t)
            let tagOK: Bool = {
                if let tag { return t.tags.contains { $0.lowercased() == tag } }
                return true
            }()
            return dateOK && searchOK && tagOK
        }
    }
    private var filteredResolvedTopics: [CDCommunityTopicEntity] {
        let tag = selectedTag?.lowercased()
        return resolvedTopics.filter { t in
            let dateOK = passesDateFilter(t)
            let searchOK = matchesSearch(t)
            let tagOK: Bool = {
                if let tag { return t.tags.contains { $0.lowercased() == tag } }
                return true
            }()
            return dateOK && searchOK && tagOK
        }
    }

    /// Markdown export of all currently-filtered resolved topics, for the ShareLink.
    private var resolvedTopicsMarkdown: String {
        filteredResolvedTopics
            .map { MarkdownExporter.markdown(for: $0) }
            .joined(separator: "\n\n---\n\n")
    }

    var body: some View {
        // FIX: Removed NavigationStack wrapper because this view is already presented 
        // inside a NavigationSplitView (iPad) or More Menu NavigationStack (iPhone).
        VStack(spacing: 0) {
            #if os(iOS)
            header
            Divider()
            #endif
            content
        }
        .navigationTitle("Community")
        #if os(macOS)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search topics")
        #endif
        .toolbar {
            #if os(macOS)
            ToolbarItem(placement: .automatic) {
                filtersMenu
            }
            #endif
            ToolbarItem(placement: .automatic) {
                Menu {
                    ShareLink(item: resolvedTopicsMarkdown) {
                        Label("Export Resolved (Markdown)", systemImage: "doc.plaintext")
                    }
                } label: { Image(systemName: "square.and.arrow.up") }
            }
            #if os(macOS)
            ToolbarItem(placement: .primaryAction) {
                Button("New Topic", systemImage: "plus") {
                    addTopicFromSearch()
                }
                .help("Create a community topic")
            }
            #endif
        }
        .sheet(isPresented: $showingAdd) {
            AddTopicSheet { title, issue in
                let t = CDCommunityTopicEntity(context: viewContext)
                t.title = title
                t.issueDescription = issue
                saveCoordinator.save(viewContext, reason: "Add community topic")
            }
        }
        #if os(iOS)
        .sheet(item: $selectedTopic) { topic in
            TopicDetailView(topic: topic) { _ in
                saveCoordinator.save(viewContext, reason: "Update community topic")
            }
        }
        #endif
    }

    private var filtersMenu: some View {
        Menu {
            Section("Date") {
                Button("All") { filterDate = nil }
                Button("Today") { filterDate = .today }
                Button("This Week") { filterDate = .thisWeek }
                Button("This Month") { filterDate = .thisMonth }
            }

            Section("Tags") {
                Button("All") { selectedTag = nil }
                ForEach(allTags, id: \.self) { tag in
                    Button(tag) { selectedTag = tag }
                }
            }
        } label: {
            Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
        }
        .help("Filter community topics")
    }

    private func addTopicFromSearch() {
        let trimmed = searchText.trimmed()
        guard !trimmed.isEmpty else {
            showingAdd = true
            return
        }

        let topic = CDCommunityTopicEntity(context: viewContext)
        topic.title = trimmed
        topic.issueDescription = ""
        saveCoordinator.save(viewContext, reason: "Quick add community topic")
        searchText = ""
        openTopic(topic)
    }

    private func openTopic(_ topic: CDCommunityTopicEntity) {
        #if os(macOS)
        guard let id = topic.id else { return }
        openWindow(id: "CommunityTopicWindow", value: id)
        #else
        selectedTopic = topic
        #endif
    }

    private var header: some View {
        MeetingsHeaderView(
            filterDate: $filterDate,
            allTags: allTags,
            selectedTag: $selectedTag,
            searchText: $searchText,
            showingAdd: $showingAdd,
            onAddTopic: { _ in addTopicFromSearch() }
        )
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                let open = filteredOpenTopics
                let resolved = filteredResolvedTopics

                SectionHeader(title: "Open Topics", systemImage: "exclamationmark.bubble.fill")
                if open.isEmpty {
                    emptyState("No open topics. \(PlatformVerb.tap) New Topic to add one.")
                } else {
                    VStack(spacing: 10) {
                        ForEach(open) { t in
                            TopicRowView(topic: t) {
                                openTopic(t)
                            }
                        }
                    }
                }

                SectionHeader(title: "Resolved Topics", systemImage: "checkmark.bubble.fill")
                if resolved.isEmpty {
                    emptyState("No resolved topics yet.")
                } else {
                    VStack(spacing: 10) {
                        ForEach(resolved) { t in
                            TopicRowView(topic: t) {
                                openTopic(t)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
    }
}

#Preview {
    CommunityMeetingsView()
        .previewEnvironment()
}
