import SwiftUI
@preconcurrency import CoreData

@Observable
@MainActor
final class TopicDetailViewModel {
    // Loading state
    var isLoading: Bool = false

    // Backing model
    var topic: CDCommunityTopicEntity?

    // Lightweight editable fields
    var title: String = ""
    var issue: String = ""
    var resolution: String = ""
    var raisedBy: String = ""
    var createdAt: Date = Date()
    var addressed: Bool = false
    var addressedDate: Date = Date()
    var tagsDraft: String = ""

    // Derived lists (loaded lazily)
    var proposedSolutions: [CDProposedSolutionEntity] = []
    var notes: [CDNote] = []
    var attachments: [CDCommunityAttachment] = []

    // MARK: - Mapping helpers

    private static func parseTags(from draft: String) -> [String] {
        draft
            .split(separator: ",")
            .map { String($0).trimmed() }
            .filter { !$0.isEmpty }
    }

    private static func joinTags(_ tags: [String]) -> String {
        tags.joined(separator: ", ")
    }

    private func populateFields(from topic: CDCommunityTopicEntity) {
        self.title = topic.title
        self.issue = topic.issueDescription
        self.resolution = topic.resolution
        self.raisedBy = topic.raisedBy
        self.createdAt = topic.createdAt ?? Date()
        self.addressed = topic.isResolved
        self.addressedDate = topic.addressedDate ?? Date()
        self.tagsDraft = Self.joinTags(topic.tags)
    }

    private func applyFields(to topic: CDCommunityTopicEntity) {
        topic.tags = Self.parseTags(from: tagsDraft)
        topic.title = title
        topic.issueDescription = issue
        topic.raisedBy = raisedBy
        topic.resolution = resolution
        topic.createdAt = createdAt
        topic.addressedDate = addressed ? addressedDate : nil
    }

    // MARK: - Fetch request builders

    private static func requestForTopic(id: UUID) -> NSFetchRequest<CDCommunityTopicEntity> {
        let request = CDFetchRequest(CDCommunityTopicEntity.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return request
    }

    private static func requestForSolutions(topicID id: UUID) -> NSFetchRequest<CDProposedSolutionEntity> {
        let request = CDFetchRequest(CDProposedSolutionEntity.self)
        request.predicate = NSPredicate(format: "topic.id == %@", id as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDProposedSolutionEntity.createdAt, ascending: true)]
        return request
    }

    private static func requestForNotes(topicID id: UUID) -> NSFetchRequest<CDNote> {
        let request = CDFetchRequest(CDNote.self)
        request.predicate = NSPredicate(format: "communityTopic.id == %@", id as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDNote.createdAt, ascending: true)]
        return request
    }

    private static func requestForAttachments(topicID id: UUID) -> NSFetchRequest<CDCommunityAttachment> {
        let request = CDFetchRequest(CDCommunityAttachment.self)
        request.predicate = NSPredicate(format: "topic.id == %@", id as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDCommunityAttachment.createdAt, ascending: true)]
        return request
    }

    func load(context: NSManagedObjectContext, topicID: UUID) async {
        // NSManagedObjectContext is not Sendable, but this function is @MainActor isolated
        // so it's safe to use the context here
        isLoading = true
        defer { isLoading = false }

        do {
            // Fetch the topic by ID
            let topicRequest = Self.requestForTopic(id: topicID)
            topicRequest.fetchLimit = 1
            let topics = try context.fetch(topicRequest)
            guard let topic = topics.first else {
                self.topic = nil
                return
            }
            self.topic = topic

            // Populate lightweight fields
            populateFields(from: topic)

            // Targeted fetches for relationships
            let solRequest = Self.requestForSolutions(topicID: topicID)
            let noteRequest = Self.requestForNotes(topicID: topicID)
            let attRequest = Self.requestForAttachments(topicID: topicID)

            // NSManagedObjectContext is not Sendable, so fetch sequentially
            self.proposedSolutions = try context.fetch(solRequest)
            self.notes = try context.fetch(noteRequest)
            self.attachments = try context.fetch(attRequest)
        } catch {
        }
    }

    func persistChanges(context: NSManagedObjectContext) {
        guard let topic else { return }
        applyFields(to: topic)
    }

    // MARK: - Relationship mutations (in-memory; caller saves)

    func addSolution(context: NSManagedObjectContext, title: String, details: String, proposedBy: String) {
        guard let topic else { return }
        let s = CDProposedSolutionEntity(context: context)
        s.id = UUID()
        s.title = title
        s.details = details
        s.proposedBy = proposedBy
        s.topic = topic
        s.createdAt = Date()
        proposedSolutions.append(s)
    }

    func toggleSolutionAdopted(_ solution: CDProposedSolutionEntity) {
        guard let idx = proposedSolutions.firstIndex(where: { $0.id == solution.id }) else { return }
        proposedSolutions[idx].isAdopted.toggle()
    }

    func deleteSolution(context: NSManagedObjectContext, _ solution: CDProposedSolutionEntity) {
        if let idx = proposedSolutions.firstIndex(where: { $0.id == solution.id }) {
            proposedSolutions.remove(at: idx)
            context.delete(solution)
        }
    }

    func addNote(context: NSManagedObjectContext, speaker: String, content: String) {
        guard let topic else { return }
        let n = CDNote(context: context)
        n.id = UUID()
        n.body = content
        n.scope = .all
        n.communityTopic = topic
        n.reporterName = speaker.isEmpty ? nil : speaker
        n.createdAt = Date()
        n.updatedAt = Date()
        notes.append(n)
    }

    func deleteNote(context: NSManagedObjectContext, _ note: CDNote) {
        if let idx = notes.firstIndex(where: { $0.id == note.id }) {
            notes.remove(at: idx)
            // Clean up associated image file before deleting the note
            note.deleteAssociatedImage()
            context.delete(note)
        }
    }

    func deleteAttachment(context: NSManagedObjectContext, _ attachment: CDCommunityAttachment) {
        if let idx = attachments.firstIndex(where: { $0.id == attachment.id }) {
            attachments.remove(at: idx)
            context.delete(attachment)
        }
    }
}
