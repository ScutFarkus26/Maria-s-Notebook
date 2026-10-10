import SwiftUI
@preconcurrency import CoreData

@Observable
final class TopicDetailViewModel {
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

    // A solution and a meeting note typed but not added yet. Save adds them,
    // so nothing she typed is dropped.
    var newSolutionTitle: String = ""
    var newSolutionDetails: String = ""
    var newSolutionProposedBy: String = ""
    var newNoteSpeaker: String = ""
    var newNoteContent: String = ""

    var proposedSolutions: [CDProposedSolutionEntity] = []
    var notes: [CDNote] = []
    var attachments: [CDCommunityAttachment] = []

    /// The fields as they were last loaded or saved.
    private var savedFields: Fields?

    /// The editable fields, compared the way Save would write them.
    private struct Fields: Equatable {
        var title: String
        var issue: String
        var resolution: String
        var raisedBy: String
        var createdAt: Date
        var addressedDate: Date?
        var tags: [String]
    }

    private var currentFields: Fields {
        Fields(
            title: title,
            issue: issue,
            resolution: resolution,
            raisedBy: raisedBy,
            createdAt: createdAt,
            addressedDate: addressed ? addressedDate : nil,
            tags: Self.parseTags(from: tagsDraft)
        )
    }

    /// Whether Save would change anything: an edited field, or a solution or
    /// note typed but not added. The sheet asks before throwing these away.
    var hasUnsavedChanges: Bool {
        currentFields != savedFields || hasPendingInput
    }

    private var hasPendingInput: Bool {
        !newSolutionTitle.trimmed().isEmpty || !newSolutionDetails.trimmed().isEmpty
            || !newNoteContent.trimmed().isEmpty
    }

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
        savedFields = currentFields
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

    // Populate view-model state synchronously from a topic entity. Called from
    // TopicDetailView's init so the view tree is stable from first render
    // (no loading→loaded swap that could race the sheet's first layout pass).
    func bind(topic: CDCommunityTopicEntity) {
        self.topic = topic
        populateFields(from: topic)

        proposedSolutions = ((topic.proposedSolutions as? Set<CDProposedSolutionEntity>) ?? [])
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        attachments = ((topic.attachments as? Set<CDCommunityAttachment>) ?? [])
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        notes = topic.unifiedNotes
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    /// Writes the edited fields, and any solution or note typed but not
    /// added, onto the topic. The caller saves, then calls `markSaved`.
    func persistChanges(context: NSManagedObjectContext) {
        guard let topic else { return }
        addPendingSolution(context: context)
        addPendingNote(context: context)
        applyFields(to: topic)
    }

    /// After a successful save: the fields as they are now are the saved ones.
    func markSaved() {
        savedFields = currentFields
    }

    // MARK: - Relationship mutations (in-memory; caller saves)

    /// Adds the solution typed into the form, if any, and clears the form.
    func addPendingSolution(context: NSManagedObjectContext) {
        let title = newSolutionTitle.trimmed()
        let details = newSolutionDetails.trimmed()
        guard !title.isEmpty || !details.isEmpty else { return }
        addSolution(context: context, title: title, details: details, proposedBy: newSolutionProposedBy.trimmed())
        newSolutionTitle = ""
        newSolutionDetails = ""
        newSolutionProposedBy = ""
    }

    /// Adds the meeting note typed into the form, if any, and clears the form.
    func addPendingNote(context: NSManagedObjectContext) {
        let content = newNoteContent.trimmed()
        guard !content.isEmpty else { return }
        addNote(context: context, speaker: newNoteSpeaker.trimmed(), content: content)
        newNoteSpeaker = ""
        newNoteContent = ""
    }

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
