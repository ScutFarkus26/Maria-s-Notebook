import SwiftUI
import CoreData

struct CommunityMeetingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDCommunityTopicEntity.createdAt, ascending: false)]) private var topics: FetchedResults<CDCommunityTopicEntity>

    @State private var showingAdd = false
    @State private var selectedTopicID: UUID?

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

    var body: some View {
        // FIX: Removed NavigationStack wrapper because this view is already presented 
        // inside a NavigationSplitView (iPad) or More Menu NavigationStack (iPhone).
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .navigationTitle("Community")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button("Export Resolved (Markdown)", systemImage: "doc.plaintext") {
                        let topicsToExport = self.filteredResolvedTopics
                        let exported: [String] = topicsToExport.map { MarkdownExporter.markdown(for: $0) }
                        let md: String = exported.joined(separator: "\n\n---\n\n")
                        MarkdownExporter.presentShare(md)
                    }
                } label: { Image(systemName: "square.and.arrow.up") }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddTopicSheet { title, issue in
                let t = CDCommunityTopicEntity(context: viewContext)
                t.title = title
                t.issueDescription = issue
                saveCoordinator.save(viewContext, reason: "Add community topic")
            }
        }
        .sheet(isPresented: Binding<Bool>(
            get: { selectedTopicID != nil },
            set: { newValue in if newValue == false { selectedTopicID = nil } }
        )) {
            if let id = selectedTopicID {
                TopicDetailView(topicID: id) { _ in
                    saveCoordinator.save(viewContext, reason: "Update community topic")
                }
            } else {
                EmptyView()
            }
        }
    }

    private var header: some View {
        MeetingsHeaderView(
            filterDate: $filterDate,
            allTags: allTags,
            selectedTag: $selectedTag,
            searchText: $searchText,
            showingAdd: $showingAdd,
            onAddTopic: { title in
                let t = CDCommunityTopicEntity(context: viewContext)
                t.title = title
                t.issueDescription = ""
                saveCoordinator.save(viewContext, reason: "Quick add community topic")
                // Clear the search text so the newly added appears and UI resets
                searchText = ""
                // Optionally open the detail editor for the new topic
                selectedTopicID = t.id
            }
        )
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                let open = filteredOpenTopics
                let resolved = filteredResolvedTopics

                SectionHeader(title: "Open Topics", systemImage: "exclamationmark.bubble.fill")
                if open.isEmpty {
                    emptyState("No open topics. Tap New Topic to add one.")
                } else {
                    VStack(spacing: 10) {
                        ForEach(open) { t in
                            TopicRowView(topic: t) {
                                selectedTopicID = t.id
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
                                selectedTopicID = t.id
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
