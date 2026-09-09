import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

@Suite("MCP Community Topic Tools")
@MainActor
struct MCPCommunityTopicToolsTests {
    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    private func topics(in context: NSManagedObjectContext) -> [CDCommunityTopicEntity] {
        context.safeFetch(CDFetchRequest(CDCommunityTopicEntity.self))
    }

    @Test("update_community_topic raises a new topic from a title")
    func raisesANewTopic() async throws {
        let (tools, context) = try makeTools()

        let output = try await tool(named: "update_community_topic", in: tools).handler([
            "title": .string("The lunch tables are never wiped"),
            "description": .string("Brought up twice this week."),
            "raised_by": .string("Etty Klein")
        ])
        #expect(output.contains("Raised [communityTopic id="))
        #expect(output.contains("raised by Etty Klein"))

        let topic = try #require(topics(in: context).first)
        #expect(topic.title == "The lunch tables are never wiped")
        #expect(topic.issueDescription == "Brought up twice this week.")
        #expect(topic.raisedBy == "Etty Klein")
        #expect(topic.addressedDate == nil)

        // It shows up in the read tool as unaddressed.
        let listed = try await tool(named: "community_topics", in: tools).handler([
            "unaddressed_only": .bool(true)
        ])
        #expect(listed.contains("The lunch tables are never wiped"))
        #expect(listed.contains("not yet discussed"))
    }

    @Test("update_community_topic refuses to raise a topic with no title")
    func refusesATitlelessTopic() async throws {
        let (tools, context) = try makeTools()

        do {
            _ = try await tool(named: "update_community_topic", in: tools).handler([
                "resolution": .string("Settled somehow.")
            ])
            Issue.record("Expected a missing-title error")
        } catch let error as MCPToolError {
            #expect(error.message.contains("needs a title"))
        }
        #expect(topics(in: context).isEmpty)
    }

    @Test("update_community_topic settles an existing topic and stamps the day")
    func settlesAnExistingTopic() async throws {
        let (tools, context) = try makeTools()
        let topic = CDCommunityTopicEntity(context: context)
        topic.title = "Where to keep the class instruments"
        CoreDataTestHelpers.save(context)
        let topicID = try #require(topic.id?.uuidString)

        let output = try await tool(named: "update_community_topic", in: tools).handler([
            "topic_id": .string(topicID),
            "discussed_on": .string("2026-09-04"),
            "resolution": .string("They live on the low shelf by the window.")
        ])
        #expect(output.contains("Updated [communityTopic id="))
        #expect(output.contains("discussed 2026-09-04"))
        #expect(output.contains("resolution"))
        #expect(MCPNotebookTools.dayString(topic.addressedDate) == "2026-09-04")
        #expect(topic.resolution == "They live on the low shelf by the window.")
    }

    @Test("update_community_topic puts a settled topic back on the agenda")
    func reopensASettledTopic() async throws {
        let (tools, context) = try makeTools()
        let topic = CDCommunityTopicEntity(context: context)
        topic.title = "Sharing the swing"
        topic.addressedDate = Date()
        CoreDataTestHelpers.save(context)
        let topicID = try #require(topic.id?.uuidString)

        let output = try await tool(named: "update_community_topic", in: tools).handler([
            "topic_id": .string(topicID),
            "discussed": .bool(false)
        ])
        #expect(output.contains("back on the agenda"))
        #expect(topic.addressedDate == nil)
    }

    @Test("update_community_topic adds proposed solutions without replacing the old ones")
    func appendsProposedSolutions() async throws {
        let (tools, context) = try makeTools()
        let topic = CDCommunityTopicEntity(context: context)
        topic.title = "Noise at the reading corner"
        let existing = CDProposedSolutionEntity(context: context)
        existing.title = "Move the corner to the back wall"
        existing.topic = topic
        CoreDataTestHelpers.save(context)
        let topicID = try #require(topic.id?.uuidString)

        let output = try await tool(named: "update_community_topic", in: tools).handler([
            "topic_id": .string(topicID),
            "proposed_solutions": .array([
                .object([
                    "solution": .string("A quiet signal anyone can raise"),
                    "proposed_by": .string("Sarah Roth"),
                    "adopted": .bool(true)
                ]),
                .object([
                    "solution": .string("Read on the porch when it is warm"),
                    "details": .string("Only with a guide outside.")
                ])
            ])
        ])
        #expect(output.contains("2 proposed solution(s)"))

        let solutions = (topic.proposedSolutions?.allObjects as? [CDProposedSolutionEntity]) ?? []
        #expect(solutions.count == 3)
        let adopted = try #require(solutions.first { $0.title == "A quiet signal anyone can raise" })
        #expect(adopted.proposedBy == "Sarah Roth")
        #expect(adopted.isAdopted)
        // The one that was already there survived.
        #expect(solutions.contains { $0.title == "Move the corner to the back wall" })
    }

    @Test("update_community_topic rejects an unknown topic id")
    func rejectsAnUnknownTopicID() async throws {
        let (tools, _) = try makeTools()

        do {
            _ = try await tool(named: "update_community_topic", in: tools).handler([
                "topic_id": .string(UUID().uuidString),
                "resolution": .string("Anything")
            ])
            Issue.record("Expected an unknown-id error")
        } catch let error as MCPToolError {
            #expect(error.message.contains("No community topic with id"))
        }
    }

    @Test("update_community_topic refuses a call that changes nothing")
    func refusesAnEmptyUpdate() async throws {
        let (tools, context) = try makeTools()
        let topic = CDCommunityTopicEntity(context: context)
        topic.title = "Snack rota"
        CoreDataTestHelpers.save(context)
        let topicID = try #require(topic.id?.uuidString)

        do {
            _ = try await tool(named: "update_community_topic", in: tools).handler([
                "topic_id": .string(topicID)
            ])
            Issue.record("Expected a no-changes error")
        } catch let error as MCPToolError {
            #expect(error.message.contains("Nothing to change"))
        }
    }
}
