import SwiftUI
import SwiftData
import Combine

@MainActor
final class TopicDetailViewModel: ObservableObject {
    // Loading state
    @Published var isLoading: Bool = false

    // Backing model
    @Published var topic: CommunityTopic?

    // Lightweight editable fields
    @Published var title: String = ""
    @Published var issue: String = ""
    @Published var resolution: String = ""
    @Published var raisedBy: String = ""
    @Published var createdAt: Date = Date()
    @Published var addressed: Bool = false
    @Published var addressedDate: Date = Date()
    @Published var tagsDraft: String = ""

    // Derived lists (loaded lazily)
    @Published var proposedSolutions: [ProposedSolution] = []
    @Published var notes: [MeetingNote] = []
    @Published var attachments: [CommunityAttachment] = []

    // MARK: - Mapping helpers

    private static func parseTags(from draft: String) -> [String] {
        draft
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func joinTags(_ tags: [String]) -> String {
        tags.joined(separator: ", ")
    }

    private func populateFields(from topic: CommunityTopic) {
        self.title = topic.title
        self.issue = topic.issueDescription
        self.resolution = topic.resolution
        self.raisedBy = topic.raisedBy
        self.createdAt = topic.createdAt
        self.addressed = topic.isResolved
        self.addressedDate = topic.addressedDate ?? Date()
        self.tagsDraft = Self.joinTags(topic.tags)
    }

    private func applyFields(to topic: CommunityTopic) {
        topic.tags = Self.parseTags(from: tagsDraft)
        topic.title = title
        topic.issueDescription = issue
        topic.raisedBy = raisedBy
        topic.resolution = resolution
        topic.createdAt = createdAt
        topic.addressedDate = addressed ? addressedDate : nil
    }

    // MARK: - Fetch descriptors

    private static func descriptorForTopic(id: UUID) -> FetchDescriptor<CommunityTopic> {
        FetchDescriptor<CommunityTopic>(
            predicate: #Predicate { $0.id == id }
        )
    }

    private static func descriptorForSolutions(topicID id: UUID) -> FetchDescriptor<ProposedSolution> {
        FetchDescriptor<ProposedSolution>(
            predicate: #Predicate { s in
                s.topic?.id == id
            },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
    }

    private static func descriptorForNotes(topicID id: UUID) -> FetchDescriptor<MeetingNote> {
        FetchDescriptor<MeetingNote>(
            predicate: #Predicate { n in
                n.topic?.id == id
            },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
    }

    private static func descriptorForAttachments(topicID id: UUID) -> FetchDescriptor<CommunityAttachment> {
        FetchDescriptor<CommunityAttachment>(
            predicate: #Predicate { a in
                a.topic?.id == id
            },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
    }

    func load(context: ModelContext, topicID: UUID) async {
        #if DEBUG
        DebugTiming.lastDetailLoadStart = Date()
        print("[DEBUG] Detail load start for topicID=\(topicID) at: \(DebugTiming.lastDetailLoadStart!)")
        #endif
        isLoading = true
        defer { isLoading = false }

        do {
            // Fetch the topic by ID
            let topics = try context.fetch(Self.descriptorForTopic(id: topicID))
            guard let topic = topics.first else {
                #if DEBUG
                print("[DEBUG] Topic not found for id \(topicID)")
                #endif
                self.topic = nil
                return
            }
            self.topic = topic

            // Populate lightweight fields
            populateFields(from: topic)

            // Targeted fetches for relationships
            let solDesc = Self.descriptorForSolutions(topicID: topicID)
            let noteDesc = Self.descriptorForNotes(topicID: topicID)
            let attDesc = Self.descriptorForAttachments(topicID: topicID)

            async let solutions = try context.fetch(solDesc)
            async let notes = try context.fetch(noteDesc)
            async let attachments = try context.fetch(attDesc)

            self.proposedSolutions = try await solutions
            self.notes = try await notes
            self.attachments = try await attachments
        } catch {
            #if DEBUG
            print("[DEBUG] Error loading topic detail: \(error)")
            #endif
        }
        #if DEBUG
        DebugTiming.lastDetailLoadEnd = Date()
        if let start = DebugTiming.lastTopicTapAt, let end = DebugTiming.lastDetailLoadEnd {
            let ms = end.timeIntervalSince(start) * 1000.0
            print("[DEBUG] Tap->detail data loaded in: \(String(format: "%.1f", ms)) ms")
        }
        #endif
    }

    func persistChanges(context: ModelContext) {
        guard let topic else { return }
        applyFields(to: topic)
    }

    // MARK: - Relationship mutations (in-memory; caller saves)

    func addSolution(context: ModelContext, title: String, details: String, proposedBy: String) {
        guard let topic else { return }
        let s = ProposedSolution(title: title, details: details, proposedBy: proposedBy, topic: topic)
        context.insert(s)
        proposedSolutions.append(s)
    }

    func toggleSolutionAdopted(_ solution: ProposedSolution) {
        guard let idx = proposedSolutions.firstIndex(where: { $0.id == solution.id }) else { return }
        proposedSolutions[idx].isAdopted.toggle()
    }

    func deleteSolution(context: ModelContext, _ solution: ProposedSolution) {
        if let idx = proposedSolutions.firstIndex(where: { $0.id == solution.id }) {
            proposedSolutions.remove(at: idx)
            context.delete(solution)
        }
    }

    func addNote(context: ModelContext, speaker: String, content: String) {
        guard let topic else { return }
        let n = MeetingNote(speaker: speaker, content: content, topic: topic)
        context.insert(n)
        notes.append(n)
    }

    func deleteNote(context: ModelContext, _ note: MeetingNote) {
        if let idx = notes.firstIndex(where: { $0.id == note.id }) {
            notes.remove(at: idx)
            context.delete(note)
        }
    }

    func deleteAttachment(context: ModelContext, _ attachment: CommunityAttachment) {
        if let idx = attachments.firstIndex(where: { $0.id == attachment.id }) {
            attachments.remove(at: idx)
            context.delete(attachment)
        }
    }
}

