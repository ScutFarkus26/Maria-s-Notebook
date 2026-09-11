//
//  MCPNotebookTools+CommunityTopics.swift
//  Maria's Notebook
//
//  The topics the class raises for community meeting. Reads and writes live
//  together because a topic is something the class works on across several
//  meetings, not reference matter a guide only consults.
//
//  Writes follow TopicDetailViewModel.applyFields: `addressedDate` carries the
//  whole discussed / not-yet-discussed state, so clearing it is what puts a
//  topic back on the agenda. Proposed solutions are appended rather than
//  replaced — the list records who suggested what, and rewriting it would
//  lose that.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Listing

    static func communityTopicsTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "community_topics",
            title: "Community Topics",
            description: "Topics the class has raised for community meeting — who brought each "
                + "one, the solutions proposed, and how it was settled.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "unaddressed_only": [
                        "type": "boolean",
                        "description": "Only topics not yet discussed (default false)"
                    ]
                ]
            ],
            annotations: .readOnly,
            handler: { arguments in
                describeCommunityTopics(arguments: arguments, in: context())
            }
        )
    }

    private static func describeCommunityTopics(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) -> String {
        let unaddressedOnly: Bool = arguments["unaddressed_only"]?.boolValue ?? false
        let all: [CDCommunityTopicEntity] = modelContext
            .safeFetch(CDFetchRequest(CDCommunityTopicEntity.self))
        var kept: [CDCommunityTopicEntity] = []
        for topic in all {
            if unaddressedOnly && topic.addressedDate != nil { continue }
            kept.append(topic)
        }
        guard !kept.isEmpty else {
            return unaddressedOnly ? "Every topic has been addressed." : "No community topics yet."
        }

        let sorted: [CDCommunityTopicEntity] = kept.sorted { lhs, rhs in
            (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
        }
        let lines = sorted.map { topic -> String in
            let id: String = topic.id?.uuidString ?? "unknown"
            var details: [String] = []
            if let broughtBy = nonEmpty(topic.broughtBy) {
                details.append("raised by \(broughtBy)")
            }
            if let addressed = topic.addressedDate {
                details.append("discussed \(dayString(addressed))")
            } else {
                details.append("not yet discussed")
            }
            let solutions: [CDProposedSolutionEntity] =
                (topic.proposedSolutions?.allObjects as? [CDProposedSolutionEntity]) ?? []
            if !solutions.isEmpty {
                details.append("\(solutions.count) proposed solution(s)")
            }
            let resolution: String = nonEmpty(topic.resolution)
                .map { "\n    Resolution: \($0)" } ?? ""
            return "- [communityTopic id=\(id)] \(topic.title) "
                + "(\(details.joined(separator: "; ")))\(resolution)"
        }
        return "\(sorted.count) topic(s):\n" + lines.joined(separator: "\n")
    }

    // MARK: - Raise Or Update

    static func updateCommunityTopicTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "update_community_topic",
            title: "Raise Or Update Community Topic",
            description: "Raise a topic for community meeting, or move one along: who brought "
                + "it, the solutions proposed, whether the class has taken it up, and how it "
                + "was settled. Pass topic_id to update; pass title to raise a new one.",
            inputSchema: updateCommunityTopicSchema,
            annotations: .idempotentWrite,
            handler: { arguments in
                try updateCommunityTopic(arguments: arguments, in: context())
            }
        )
    }

    private static let updateCommunityTopicSchema: JSONValue = [
        "type": "object",
        "properties": [
            "topic_id": [
                "type": "string",
                "description": "The topic to update, from community_topics. Omit to raise a new one."
            ],
            "title": ["type": "string", "description": "What the topic is"],
            "description": ["type": "string", "description": "The detail behind it"],
            "raised_by": [
                "type": "string",
                "description": "Who brought it; pass an empty string to clear it"
            ],
            "proposed_solutions": [
                "type": "array",
                "description": .string("Solutions the class put forward. These are ADDED to the "
                    + "solutions already on the topic rather than replacing them, so pass only "
                    + "what is new."),
                "items": [
                    "type": "object",
                    "properties": [
                        "solution": [
                            "type": "string",
                            "description": "The suggestion, as it was put"
                        ],
                        "details": [
                            "type": "string",
                            "description": "Any elaboration on how it would work"
                        ],
                        "proposed_by": [
                            "type": "string",
                            "description": "Who suggested it"
                        ],
                        "adopted": [
                            "type": "boolean",
                            "description": "Whether the class agreed to try it (default false)"
                        ]
                    ],
                    "required": ["solution"]
                ]
            ],
            "discussed": [
                "type": "boolean",
                "description": .string("Whether the class has taken it up. True stamps today "
                    + "unless discussed_on says otherwise; false clears the date and puts the "
                    + "topic back on the agenda.")
            ],
            "discussed_on": [
                "type": "string",
                "description": "The day it was discussed, YYYY-MM-DD"
            ],
            "resolution": [
                "type": "string",
                "description": "How it was settled"
            ]
        ]
    ]

    private static func updateCommunityTopic(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let topic: CDCommunityTopicEntity
        let verb: String
        if let reference = nonEmpty(arguments["topic_id"]?.stringValue) {
            topic = try resolveCommunityTopic(reference, in: modelContext)
            verb = "Updated"
        } else {
            guard nonEmpty(arguments["title"]?.stringValue) != nil else {
                throw MCPToolError("Raising a community topic needs a title.")
            }
            topic = CDCommunityTopicEntity(context: modelContext)
            verb = "Raised"
        }

        var changes: [String] = []
        changes += applyTopicText(arguments, to: topic)
        changes += try applyTopicDiscussion(arguments, to: topic)
        changes += try applyTopicSolutions(arguments, to: topic, in: modelContext)

        guard !changes.isEmpty else {
            throw MCPToolError("Nothing to change — pass at least one field.")
        }
        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The community topic could not be saved.")
        }
        let id: String = topic.id?.uuidString ?? "unknown"
        return "\(verb) [communityTopic id=\(id)] \(topic.title): \(changes.joined(separator: ", "))."
    }

    private static func applyTopicText(
        _ arguments: [String: JSONValue], to topic: CDCommunityTopicEntity
    ) -> [String] {
        var changes: [String] = []
        if let title = nonEmpty(arguments["title"]?.stringValue) {
            topic.title = title
            changes.append("title")
        }
        if let detail = arguments["description"]?.stringValue {
            topic.issueDescription = detail.trimmed()
            changes.append("description")
        }
        // An empty raised_by is meaningful — it clears the field — so read the
        // raw value rather than nonEmpty.
        if let raisedBy = arguments["raised_by"]?.stringValue?.trimmed() {
            topic.raisedBy = raisedBy
            changes.append(raisedBy.isEmpty ? "cleared who raised it" : "raised by \(raisedBy)")
        }
        if let resolution = nonEmpty(arguments["resolution"]?.stringValue) {
            topic.resolution = resolution
            changes.append("resolution")
        }
        return changes
    }

    /// `addressedDate` is the discussed / not-yet-discussed state on its own,
    /// the way TopicDetailViewModel treats it, so `discussed: false` clears it
    /// rather than setting a second flag.
    private static func applyTopicDiscussion(
        _ arguments: [String: JSONValue], to topic: CDCommunityTopicEntity
    ) throws -> [String] {
        let day = try dayArgument(arguments, "discussed_on")
        let discussed = arguments["discussed"]?.boolValue
        if discussed == false {
            guard day == nil else {
                throw MCPToolError("Pass either discussed: false or discussed_on, not both.")
            }
            guard topic.addressedDate != nil else { return [] }
            topic.addressedDate = nil
            return ["back on the agenda"]
        }
        guard discussed == true || day != nil else { return [] }
        let stamped = day ?? topic.addressedDate ?? Date()
        topic.addressedDate = stamped
        return ["discussed \(dayString(stamped))"]
    }

    /// Solutions accumulate across meetings, so new ones are appended. They are
    /// built here rather than in the caller so a malformed entry throws before
    /// anything is saved.
    private static func applyTopicSolutions(
        _ arguments: [String: JSONValue], to topic: CDCommunityTopicEntity,
        in modelContext: NSManagedObjectContext
    ) throws -> [String] {
        guard let entries = arguments["proposed_solutions"]?.arrayValue, !entries.isEmpty else {
            return []
        }
        for entry in entries {
            guard let fields = entry.objectValue else {
                throw MCPToolError("Each proposed_solutions entry must be an object.")
            }
            let solution = CDProposedSolutionEntity(context: modelContext)
            solution.title = try requireString(fields, "solution")
            solution.details = fields["details"]?.stringValue?.trimmed() ?? ""
            solution.proposedBy = fields["proposed_by"]?.stringValue?.trimmed() ?? ""
            solution.isAdopted = fields["adopted"]?.boolValue ?? false
            solution.topic = topic
        }
        return ["\(entries.count) proposed solution(s)"]
    }

    private static func resolveCommunityTopic(
        _ reference: String, in modelContext: NSManagedObjectContext
    ) throws -> CDCommunityTopicEntity {
        guard let id = UUID(uuidString: reference) else {
            throw MCPToolError("topic_id must be a uuid, got \"\(reference)\".")
        }
        let request = CDFetchRequest(CDCommunityTopicEntity.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        guard let topic = modelContext.safeFetch(request).first else {
            throw MCPToolError("No community topic with id \(reference) was found.")
        }
        return topic
    }
}
