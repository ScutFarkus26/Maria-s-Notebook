import SwiftUI
@preconcurrency import SwiftData
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
    @Published var notes: [Note] = []
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

    private static func descriptorForNotes(topicID id: UUID) -> FetchDescriptor<Note> {
        FetchDescriptor<Note>(
            predicate: #Predicate { n in
                n.communityTopic?.id == id
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
        // ModelContext is not Sendable, but this function is @MainActor isolated
        // so it's safe to use the context here
        isLoading = true
        defer { isLoading = false }

        do {
            // Fetch the topic by ID
            let topics = try context.fetch(Self.descriptorForTopic(id: topicID))
            guard let topic = topics.first else {
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

            // ModelContext is not Sendable, so fetch sequentially
            self.proposedSolutions = try context.fetch(solDesc)
            self.notes = try context.fetch(noteDesc)
            self.attachments = try context.fetch(attDesc)
        } catch {
        }
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
        let n = Note(
            body: content,
            scope: .all,
            communityTopic: topic,
            reporterName: speaker.isEmpty ? nil : speaker
        )
        context.insert(n)
        notes.append(n)
    }

    func deleteNote(context: ModelContext, _ note: Note) {
        if let idx = notes.firstIndex(where: { $0.id == note.id }) {
            notes.remove(at: idx)
            // Clean up associated image file before deleting the note
            note.deleteAssociatedImage()
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

