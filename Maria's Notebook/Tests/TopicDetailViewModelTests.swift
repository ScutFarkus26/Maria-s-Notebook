#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Helper Factory

@MainActor
private func makeTopicContainer() throws -> ModelContainer {
    return try makeTestContainer(for: [
        CommunityTopic.self,
        ProposedSolution.self,
        CommunityAttachment.self,
        Note.self,
    ])
}

private func makeTestCommunityTopic(
    id: UUID = UUID(),
    title: String = "Test Topic",
    issueDescription: String = "Test issue description",
    resolution: String = "",
    raisedBy: String = "",
    createdAt: Date = Date(),
    addressedDate: Date? = nil
) -> CommunityTopic {
    return CommunityTopic(
        id: id,
        title: title,
        issueDescription: issueDescription,
        createdAt: createdAt,
        addressedDate: addressedDate,
        resolution: resolution
    )
}

private func makeTestProposedSolution(
    id: UUID = UUID(),
    title: String = "Test Solution",
    details: String = "Test details",
    proposedBy: String = "Someone",
    isAdopted: Bool = false,
    topic: CommunityTopic? = nil
) -> ProposedSolution {
    return ProposedSolution(
        id: id,
        title: title,
        details: details,
        proposedBy: proposedBy,
        isAdopted: isAdopted,
        topic: topic
    )
}

// MARK: - Initialization Tests

@Suite("TopicDetailViewModel Initialization Tests", .serialized)
@MainActor
struct TopicDetailViewModelInitializationTests {

    @Test("ViewModel initializes with default state")
    func initializesWithDefaultState() {
        let vm = TopicDetailViewModel()

        #expect(vm.isLoading == false)
        #expect(vm.topic == nil)
        #expect(vm.title == "")
        #expect(vm.issue == "")
        #expect(vm.resolution == "")
        #expect(vm.raisedBy == "")
        #expect(vm.addressed == false)
        #expect(vm.tagsDraft == "")
        #expect(vm.proposedSolutions.isEmpty)
        #expect(vm.notes.isEmpty)
        #expect(vm.attachments.isEmpty)
    }
}

// MARK: - Loading Tests

@Suite("TopicDetailViewModel Loading Tests", .serialized)
@MainActor
struct TopicDetailViewModelLoadingTests {

    @Test("load populates fields from topic")
    func loadPopulatesFieldsFromTopic() async throws {
        let container = try makeTopicContainer()
        let context = ModelContext(container)
        let vm = TopicDetailViewModel()

        let topic = makeTestCommunityTopic(
            title: "Playground Safety",
            issueDescription: "Children running near swings",
            resolution: "Add safety markers",
            raisedBy: "Parent Council"
        )
        topic.tags = ["Safety", "Playground"]
        context.insert(topic)
        try context.save()

        await vm.load(context: context, topicID: topic.id)

        #expect(vm.topic?.id == topic.id)
        #expect(vm.title == "Playground Safety")
        #expect(vm.issue == "Children running near swings")
        #expect(vm.resolution == "Add safety markers")
        #expect(vm.raisedBy == "Parent Council")
        #expect(vm.tagsDraft == "Safety, Playground")
    }

    @Test("load handles non-existent topic")
    func loadHandlesNonExistentTopic() async throws {
        let container = try makeTopicContainer()
        let context = ModelContext(container)
        let vm = TopicDetailViewModel()

        await vm.load(context: context, topicID: UUID())

        #expect(vm.topic == nil)
    }

    @Test("load populates addressed flag correctly")
    func loadPopulatesAddressedFlagCorrectly() async throws {
        let container = try makeTopicContainer()
        let context = ModelContext(container)
        let vm = TopicDetailViewModel()

        let addressedDate = Date()
        let topic = makeTestCommunityTopic(
            title: "Test Topic",
            addressedDate: addressedDate
        )
        context.insert(topic)
        try context.save()

        await vm.load(context: context, topicID: topic.id)

        #expect(vm.addressed == true)
    }

    @Test("load loads proposed solutions")
    func loadLoadsProposedSolutions() async throws {
        let container = try makeTopicContainer()
        let context = ModelContext(container)
        let vm = TopicDetailViewModel()

        let topic = makeTestCommunityTopic(title: "Test Topic")
        context.insert(topic)

        let solution1 = makeTestProposedSolution(title: "Solution 1", topic: topic)
        let solution2 = makeTestProposedSolution(title: "Solution 2", topic: topic)
        context.insert(solution1)
        context.insert(solution2)
        try context.save()

        await vm.load(context: context, topicID: topic.id)

        #expect(vm.proposedSolutions.count == 2)
    }
}

// MARK: - Persist Changes Tests

@Suite("TopicDetailViewModel Persist Changes Tests", .serialized)
@MainActor
struct TopicDetailViewModelPersistChangesTests {

    @Test("persistChanges updates topic title")
    func persistChangesUpdatesTopicTitle() async throws {
        let container = try makeTopicContainer()
        let context = ModelContext(container)
        let vm = TopicDetailViewModel()

        let topic = makeTestCommunityTopic(title: "Original Title")
        context.insert(topic)
        try context.save()

        await vm.load(context: context, topicID: topic.id)
        vm.title = "Updated Title"
        vm.persistChanges(context: context)

        #expect(topic.title == "Updated Title")
    }

    @Test("persistChanges updates topic issue description")
    func persistChangesUpdatesTopicIssue() async throws {
        let container = try makeTopicContainer()
        let context = ModelContext(container)
        let vm = TopicDetailViewModel()

        let topic = makeTestCommunityTopic(issueDescription: "Original issue")
        context.insert(topic)
        try context.save()

        await vm.load(context: context, topicID: topic.id)
        vm.issue = "Updated issue"
        vm.persistChanges(context: context)

        #expect(topic.issueDescription == "Updated issue")
    }

    @Test("persistChanges updates topic resolution")
    func persistChangesUpdatesTopicResolution() async throws {
        let container = try makeTopicContainer()
        let context = ModelContext(container)
        let vm = TopicDetailViewModel()

        let topic = makeTestCommunityTopic(resolution: "")
        context.insert(topic)
        try context.save()

        await vm.load(context: context, topicID: topic.id)
        vm.resolution = "New resolution"
        vm.persistChanges(context: context)

        #expect(topic.resolution == "New resolution")
    }

    @Test("persistChanges updates topic raisedBy")
    func persistChangesUpdatesTopicRaisedBy() async throws {
        let container = try makeTopicContainer()
        let context = ModelContext(container)
        let vm = TopicDetailViewModel()

        let topic = makeTestCommunityTopic(raisedBy: "")
        context.insert(topic)
        try context.save()

        await vm.load(context: context, topicID: topic.id)
        vm.raisedBy = "Teacher"
        vm.persistChanges(context: context)

        #expect(topic.raisedBy == "Teacher")
    }

    @Test("persistChanges parses and updates tags")
    func persistChangesParsesTags() async throws {
        let container = try makeTopicContainer()
        let context = ModelContext(container)
        let vm = TopicDetailViewModel()

        let topic = makeTestCommunityTopic()
        context.insert(topic)
        try context.save()

        await vm.load(context: context, topicID: topic.id)
        vm.tagsDraft = "Safety, Environment, Curriculum"
        vm.persistChanges(context: context)

        #expect(topic.tags.count == 3)
        #expect(topic.tags.contains("Safety"))
        #expect(topic.tags.contains("Environment"))
        #expect(topic.tags.contains("Curriculum"))
    }

    @Test("persistChanges handles empty tags")
    func persistChangesHandlesEmptyTags() async throws {
        let container = try makeTopicContainer()
        let context = ModelContext(container)
        let vm = TopicDetailViewModel()

        let topic = makeTestCommunityTopic()
        topic.tags = ["Existing"]
        context.insert(topic)
        try context.save()

        await vm.load(context: context, topicID: topic.id)
        vm.tagsDraft = ""
        vm.persistChanges(context: context)

        #expect(topic.tags.isEmpty)
    }

    @Test("persistChanges does nothing when topic is nil")
    func persistChangesDoesNothingWhenTopicNil() {
        let vm = TopicDetailViewModel()
        let context = try! makeTopicContainer().mainContext

        vm.title = "Should not be saved"
        vm.persistChanges(context: context)

        // Just verify no crash - topic is nil so nothing happens
        #expect(vm.topic == nil)
    }
}

// MARK: - Solution Management Tests

@Suite("TopicDetailViewModel Solution Management Tests", .serialized)
@MainActor
struct TopicDetailViewModelSolutionTests {

    @Test("addSolution creates and adds new solution")
    func addSolutionCreatesNewSolution() async throws {
        let container = try makeTopicContainer()
        let context = ModelContext(container)
        let vm = TopicDetailViewModel()

        let topic = makeTestCommunityTopic()
        context.insert(topic)
        try context.save()

        await vm.load(context: context, topicID: topic.id)

        vm.addSolution(context: context, title: "New Solution", details: "Solution details", proposedBy: "Teacher")

        #expect(vm.proposedSolutions.count == 1)
        #expect(vm.proposedSolutions[0].title == "New Solution")
        #expect(vm.proposedSolutions[0].details == "Solution details")
        #expect(vm.proposedSolutions[0].proposedBy == "Teacher")
    }

    @Test("addSolution does nothing when topic is nil")
    func addSolutionDoesNothingWhenTopicNil() throws {
        let container = try makeTopicContainer()
        let context = ModelContext(container)
        let vm = TopicDetailViewModel()

        vm.addSolution(context: context, title: "Test", details: "Test", proposedBy: "Test")

        #expect(vm.proposedSolutions.isEmpty)
    }

    @Test("toggleSolutionAdopted toggles adopted status")
    func toggleSolutionAdoptedTogglesStatus() async throws {
        let container = try makeTopicContainer()
        let context = ModelContext(container)
        let vm = TopicDetailViewModel()

        let topic = makeTestCommunityTopic()
        context.insert(topic)

        let solution = makeTestProposedSolution(title: "Solution", isAdopted: false, topic: topic)
        context.insert(solution)
        try context.save()

        await vm.load(context: context, topicID: topic.id)

        #expect(vm.proposedSolutions[0].isAdopted == false)

        vm.toggleSolutionAdopted(vm.proposedSolutions[0])

        #expect(vm.proposedSolutions[0].isAdopted == true)

        vm.toggleSolutionAdopted(vm.proposedSolutions[0])

        #expect(vm.proposedSolutions[0].isAdopted == false)
    }

    @Test("deleteSolution removes solution from list")
    func deleteSolutionRemovesSolution() async throws {
        let container = try makeTopicContainer()
        let context = ModelContext(container)
        let vm = TopicDetailViewModel()

        let topic = makeTestCommunityTopic()
        context.insert(topic)

        let solution = makeTestProposedSolution(title: "To Delete", topic: topic)
        context.insert(solution)
        try context.save()

        await vm.load(context: context, topicID: topic.id)

        #expect(vm.proposedSolutions.count == 1)

        vm.deleteSolution(context: context, vm.proposedSolutions[0])

        #expect(vm.proposedSolutions.isEmpty)
    }

    @Test("deleteSolution handles non-existent solution gracefully")
    func deleteSolutionHandlesNonExistent() async throws {
        let container = try makeTopicContainer()
        let context = ModelContext(container)
        let vm = TopicDetailViewModel()

        let topic = makeTestCommunityTopic()
        context.insert(topic)
        try context.save()

        await vm.load(context: context, topicID: topic.id)

        let fakeSolution = makeTestProposedSolution(title: "Fake")

        // Should not crash
        vm.deleteSolution(context: context, fakeSolution)

        #expect(vm.proposedSolutions.isEmpty)
    }
}

// MARK: - Note Management Tests

@Suite("TopicDetailViewModel Note Management Tests", .serialized)
@MainActor
struct TopicDetailViewModelNoteTests {

    @Test("addNote creates and adds new note")
    func addNoteCreatesNewNote() async throws {
        let container = try makeTopicContainer()
        let context = ModelContext(container)
        let vm = TopicDetailViewModel()

        let topic = makeTestCommunityTopic()
        context.insert(topic)
        try context.save()

        await vm.load(context: context, topicID: topic.id)

        vm.addNote(context: context, speaker: "Teacher", content: "Note content")

        #expect(vm.notes.count == 1)
        #expect(vm.notes[0].body == "Note content")
        #expect(vm.notes[0].reporterName == "Teacher")
    }

    @Test("addNote handles empty speaker")
    func addNoteHandlesEmptySpeaker() async throws {
        let container = try makeTopicContainer()
        let context = ModelContext(container)
        let vm = TopicDetailViewModel()

        let topic = makeTestCommunityTopic()
        context.insert(topic)
        try context.save()

        await vm.load(context: context, topicID: topic.id)

        vm.addNote(context: context, speaker: "", content: "Note content")

        #expect(vm.notes.count == 1)
        #expect(vm.notes[0].reporterName == nil)
    }

    @Test("addNote does nothing when topic is nil")
    func addNoteDoesNothingWhenTopicNil() throws {
        let container = try makeTopicContainer()
        let context = ModelContext(container)
        let vm = TopicDetailViewModel()

        vm.addNote(context: context, speaker: "Test", content: "Test")

        #expect(vm.notes.isEmpty)
    }

    @Test("deleteNote removes note from list")
    func deleteNoteRemovesNote() async throws {
        let container = try makeTopicContainer()
        let context = ModelContext(container)
        let vm = TopicDetailViewModel()

        let topic = makeTestCommunityTopic()
        context.insert(topic)
        try context.save()

        await vm.load(context: context, topicID: topic.id)

        vm.addNote(context: context, speaker: "Teacher", content: "To Delete")

        #expect(vm.notes.count == 1)

        vm.deleteNote(context: context, vm.notes[0])

        #expect(vm.notes.isEmpty)
    }
}

// MARK: - Attachment Management Tests

@Suite("TopicDetailViewModel Attachment Management Tests", .serialized)
@MainActor
struct TopicDetailViewModelAttachmentTests {

    @Test("deleteAttachment removes attachment from list")
    func deleteAttachmentRemovesAttachment() async throws {
        let container = try makeTopicContainer()
        let context = ModelContext(container)
        let vm = TopicDetailViewModel()

        let topic = makeTestCommunityTopic()
        context.insert(topic)

        let attachment = CommunityAttachment(
            filename: "test.jpg",
            kind: .photo,
            topic: topic
        )
        context.insert(attachment)
        try context.save()

        await vm.load(context: context, topicID: topic.id)

        #expect(vm.attachments.count == 1)

        vm.deleteAttachment(context: context, vm.attachments[0])

        #expect(vm.attachments.isEmpty)
    }

    @Test("deleteAttachment handles non-existent attachment gracefully")
    func deleteAttachmentHandlesNonExistent() async throws {
        let container = try makeTopicContainer()
        let context = ModelContext(container)
        let vm = TopicDetailViewModel()

        let topic = makeTestCommunityTopic()
        context.insert(topic)
        try context.save()

        await vm.load(context: context, topicID: topic.id)

        let fakeAttachment = CommunityAttachment(filename: "fake.jpg")

        // Should not crash
        vm.deleteAttachment(context: context, fakeAttachment)

        #expect(vm.attachments.isEmpty)
    }
}

// MARK: - Tag Parsing Tests

@Suite("TopicDetailViewModel Tag Parsing Tests", .serialized)
@MainActor
struct TopicDetailViewModelTagParsingTests {

    @Test("Tags are joined correctly when loading")
    func tagsJoinedCorrectlyOnLoad() async throws {
        let container = try makeTopicContainer()
        let context = ModelContext(container)
        let vm = TopicDetailViewModel()

        let topic = makeTestCommunityTopic()
        topic.tags = ["Safety", "Curriculum", "Budget"]
        context.insert(topic)
        try context.save()

        await vm.load(context: context, topicID: topic.id)

        #expect(vm.tagsDraft == "Safety, Curriculum, Budget")
    }

    @Test("Tags handle whitespace correctly")
    func tagsHandleWhitespaceCorrectly() async throws {
        let container = try makeTopicContainer()
        let context = ModelContext(container)
        let vm = TopicDetailViewModel()

        let topic = makeTestCommunityTopic()
        context.insert(topic)
        try context.save()

        await vm.load(context: context, topicID: topic.id)
        vm.tagsDraft = "  Safety  ,  Curriculum  ,   Budget   "
        vm.persistChanges(context: context)

        #expect(topic.tags.count == 3)
        #expect(topic.tags.contains("Safety"))
        #expect(topic.tags.contains("Curriculum"))
        #expect(topic.tags.contains("Budget"))
    }

    @Test("Tags filter out empty strings")
    func tagsFilterOutEmptyStrings() async throws {
        let container = try makeTopicContainer()
        let context = ModelContext(container)
        let vm = TopicDetailViewModel()

        let topic = makeTestCommunityTopic()
        context.insert(topic)
        try context.save()

        await vm.load(context: context, topicID: topic.id)
        vm.tagsDraft = "Safety,,,Curriculum,,Budget"
        vm.persistChanges(context: context)

        #expect(topic.tags.count == 3)
    }
}

// MARK: - Addressed Date Tests

@Suite("TopicDetailViewModel Addressed Date Tests", .serialized)
@MainActor
struct TopicDetailViewModelAddressedDateTests {

    @Test("persistChanges sets addressedDate when addressed is true")
    func persistChangesSetsAddressedDateWhenTrue() async throws {
        let container = try makeTopicContainer()
        let context = ModelContext(container)
        let vm = TopicDetailViewModel()

        let topic = makeTestCommunityTopic(addressedDate: nil)
        context.insert(topic)
        try context.save()

        await vm.load(context: context, topicID: topic.id)
        vm.addressed = true
        vm.addressedDate = Date()
        vm.persistChanges(context: context)

        #expect(topic.addressedDate != nil)
    }

    @Test("persistChanges clears addressedDate when addressed is false")
    func persistChangesClearsAddressedDateWhenFalse() async throws {
        let container = try makeTopicContainer()
        let context = ModelContext(container)
        let vm = TopicDetailViewModel()

        let topic = makeTestCommunityTopic(addressedDate: Date())
        context.insert(topic)
        try context.save()

        await vm.load(context: context, topicID: topic.id)
        vm.addressed = false
        vm.persistChanges(context: context)

        #expect(topic.addressedDate == nil)
    }
}

#endif
