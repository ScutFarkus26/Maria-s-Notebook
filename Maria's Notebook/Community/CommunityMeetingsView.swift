import SwiftUI
import SwiftData

struct CommunityMeetingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    @Query(sort: [SortDescriptor(\CommunityTopic.createdAt, order: .reverse)])
    private var topics: [CommunityTopic]

    @State private var showingAdd = false
    @State private var selectedTopicID: UUID? = nil

    enum DateFilter { case today, thisWeek, thisMonth, last30, thisYear }
    @State private var filterDate: DateFilter? = nil
    @State private var selectedTag: String? = nil
    @State private var searchText: String = ""

    private var openTopics: [CommunityTopic] { topics.filter { !$0.isResolved } }
    private var resolvedTopics: [CommunityTopic] { topics.filter { $0.isResolved } }

    private var allTags: [String] {
        let raw = topics.flatMap { $0.tags }
        let trimmed = raw.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let filtered = trimmed.filter { !$0.isEmpty }
        return Array(Set(filtered)).sorted()
    }

    private func passesDateFilter(_ t: CommunityTopic) -> Bool {
        guard let f = filterDate else { return true }
        let cal = Calendar.current
        let now = Date()
        switch f {
        case .today:
            return cal.isDate(t.createdAt, inSameDayAs: now)
        case .thisWeek:
            return cal.isDate(t.createdAt, equalTo: now, toGranularity: .weekOfYear)
        case .thisMonth:
            return cal.isDate(t.createdAt, equalTo: now, toGranularity: .month)
        case .last30:
            return t.createdAt >= cal.date(byAdding: .day, value: -30, to: now)!
        case .thisYear:
            return cal.isDate(t.createdAt, equalTo: now, toGranularity: .year)
        }
    }

    private func matchesSearch(_ t: CommunityTopic) -> Bool {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return true }
        let qLower = q.lowercased()

        let baseParts = [t.title, t.issueDescription, t.resolution]
        let baseText = baseParts.joined(separator: "\n")

        let solutionsText = (t.proposedSolutions ?? []).map { part in
            let title = part.title
            let details = part.details
            return "\(title)\n\(details)"
        }.joined(separator: "\n")

        let notesText = (t.notes ?? []).map { note in
            let speaker = note.speaker
            let content = note.content
            return "\(speaker)\n\(content)"
        }.joined(separator: "\n")

        var pieces: [String] = []
        pieces.append(baseText)
        pieces.append(solutionsText)
        pieces.append(notesText)
        let combinedLower: String = pieces.joined(separator: "\n").lowercased()
        return combinedLower.contains(qLower)
    }

    private var filteredOpenTopics: [CommunityTopic] {
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
    private var filteredResolvedTopics: [CommunityTopic] {
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
        .navigationTitle("Community Meetings")
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
                let t = CommunityTopic(title: title, issueDescription: issue)
                modelContext.insert(t)
                _ = saveCoordinator.save(modelContext, reason: "Add community topic")
            }
        }
        .sheet(isPresented: Binding<Bool>(
            get: { selectedTopicID != nil },
            set: { newValue in if newValue == false { selectedTopicID = nil } }
        )) {
            if let id = selectedTopicID {
                TopicDetailView(topicID: id) { _ in
                    _ = saveCoordinator.save(modelContext, reason: "Update community topic")
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
                let t = CommunityTopic(title: title, issueDescription: "")
                modelContext.insert(t)
                _ = saveCoordinator.save(modelContext, reason: "Quick add community topic")
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
    let container = ModelContainer.preview
    let ctx = container.mainContext

    let t1 = CommunityTopic(title: "Playground supervision", issueDescription: "We need clearer rotation and visibility for lower elementary.")
    let s1 = ProposedSolution(title: "Color-coded vests", details: "Assign vests and zones per day.", proposedBy: "Maria", topic: t1)
    let s2 = ProposedSolution(title: "Student helpers", details: "Older students pair with guides.", proposedBy: "Ami", topic: t1)
    t1.proposedSolutions = [s1, s2]
    t1.notes = [MeetingNote(speaker: "John", content: "Safety near swings is the main concern.", topic: t1)]

    let t2 = CommunityTopic(title: "Library noise", issueDescription: "Afternoon work cycle is too loud.", addressedDate: Date(), resolution: "Post visual noise meter and soft music.")
    let s3 = ProposedSolution(title: "Quiet corners", details: "Add more rugs and dividers.", proposedBy: "Sara", topic: t2)
    t2.proposedSolutions = [s3]

    ctx.insert(t1)
    ctx.insert(t2)

    return CommunityMeetingsView()
        .previewEnvironment(using: container)
}

