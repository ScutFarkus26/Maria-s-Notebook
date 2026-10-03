//
//  NotebookTools+Meetings.swift
//  Cosmic Daybook
//
//  Meeting and follow-up tools for on-device chat. Each tool is a thin
//  bridge onto the MCP handlers in MCPNotebookTools+Meetings.swift — one
//  implementation behind both surfaces — so argument validation, save
//  paths, and citation strings cannot drift between chat and Claude
//  Desktop. Unlike MCP clients, chat has no per-call approval UI, so the
//  write tools' descriptions restrict them to explicit requests from the
//  guide, and expected failures come back as plain replies rather than
//  thrown errors, matching the other chat tools.
//

import CoreData
import Foundation
import OSLog

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels

extension NotebookTools {
    /// The meeting and follow-up bridges, attached after the lookups.
    static var meetingTools: [any Tool] {
        [ListOpenFollowUpsTool(), RecordStudentMeetingTool(), AddFollowUpTool(), ResolveFollowUpTool()]
    }
}

/// Runs one bridged MCP handler, converting expected tool errors into
/// replies the model can relay to the guide.
@MainActor
private func bridgedNotebookOperation(_ operation: () throws -> String) -> String {
    do {
        return try operation()
    } catch let error as MCPToolError {
        return error.message
    } catch {
        // The reply can reach the guide word for word, so it stays plain; the
        // raw error goes to the log.
        Logger.ai.error("Notebook tool failed: \(error.localizedDescription, privacy: .public)")
        return "The notebook couldn't do that. Try again, or do it in the app."
    }
}

/// Records a completed student meeting through the same path as the in-app
/// meeting form; new goals become open focus items.
struct RecordStudentMeetingTool: Tool {
    var contextProvider: MCPContextProvider = { ChatToolContext.context }
    let name = "recordStudentMeeting"
    let description = "Record a completed student meeting (conference) in the student's history. "
        + "Use ONLY when the guide explicitly asks to record or file a meeting — never for "
        + "something mentioned in passing."

    @Generable(description: "Record student meeting arguments")
    struct Arguments {
        @Guide(description: "The student met with: a first name, full name, or nickname")
        var student: String
        @Guide(description: "Meeting date as YYYY-MM-DD, or empty for today")
        var date: String
        @Guide(description: "How the work is going: plan follow-through, what went well or was "
            + "hard, social and community notes; empty if not discussed")
        var reflection: String
        @Guide(description: "Lessons the student asked for or is ready for; empty if none")
        var lessonRequests: String
        @Guide(description: "Private notes only the guide sees; empty if none")
        var guideNotes: String
        @Guide(description: "New goals or next steps agreed in this meeting; each becomes an "
            + "open focus item carried to the next conference")
        var goals: [String]
    }

    func call(arguments: Arguments) async throws -> String {
        let toolArguments: [String: JSONValue] = [
            "student": .string(arguments.student),
            "date": .string(arguments.date),
            "reflection": .string(arguments.reflection),
            "lesson_requests": .string(arguments.lessonRequests),
            "guide_notes": .string(arguments.guideNotes),
            "goals": .array(arguments.goals.map { .string($0) })
        ]
        let contextProvider = contextProvider
        return await MainActor.run {
            bridgedNotebookOperation {
                try MCPNotebookTools.recordMeeting(arguments: toolArguments, in: contextProvider())
            }
        }
    }
}

/// Adds a follow-up to the guide's todo list through the same path as the
/// in-app new-todo form, including student tag syncing.
struct AddFollowUpTool: Tool {
    var contextProvider: MCPContextProvider = { ChatToolContext.context }
    let name = "addFollowUp"
    let description = "Add a follow-up to the guide's todo list — something owed to a student, "
        + "a parent, an assistant, or the guide themself. Use ONLY when the guide explicitly "
        + "asks to add a follow-up or todo. For a goal a student owns, use "
        + "recordStudentMeeting's goals instead."

    @Generable(description: "Add follow-up arguments")
    struct Arguments {
        @Guide(description: "What is owed, phrased as an action")
        var title: String
        @Guide(description: "Optional detail behind the follow-up; empty if none")
        var notes: String
        @Guide(description: "Students this follow-up concerns; empty list if none")
        var studentNames: [String]
        @Guide(description: "Due date as YYYY-MM-DD, or empty if there is no deadline")
        var dueDate: String
    }

    func call(arguments: Arguments) async throws -> String {
        let toolArguments: [String: JSONValue] = [
            "title": .string(arguments.title),
            "notes": .string(arguments.notes),
            "student_names": .array(arguments.studentNames.map { .string($0) }),
            "due_date": .string(arguments.dueDate)
        ]
        let contextProvider = contextProvider
        let reply = await MainActor.run {
            bridgedNotebookOperation {
                try MCPNotebookTools.addFollowUp(arguments: toolArguments, in: contextProvider())
            }
        }
        // The same-day duplicate guard ends by offering `force: true`, which
        // chat can't pass; the guide files a second copy in the app instead.
        return reply.replacingOccurrences(of: MCPNotebookTools.duplicateForceHint, with: ".")
    }
}

/// Marks a follow-up done: completes a todo or resolves a student's open
/// goal (focus item) by id.
struct ResolveFollowUpTool: Tool {
    var contextProvider: MCPContextProvider = { ChatToolContext.context }
    let name = "resolveFollowUp"
    let description = "Mark a follow-up done: completes a todo, or resolves a student's open "
        + "goal, by the id shown in listOpenFollowUps. Use ONLY when the guide explicitly says "
        + "an item is done or no longer needed."

    @Generable(description: "Resolve follow-up arguments")
    struct Arguments {
        @Guide(description: "The todo or focus item UUID from listOpenFollowUps")
        var id: String
    }

    func call(arguments: Arguments) async throws -> String {
        let toolArguments: [String: JSONValue] = ["id": .string(arguments.id)]
        let contextProvider = contextProvider
        return await MainActor.run {
            bridgedNotebookOperation {
                try MCPNotebookTools.resolveFollowUp(arguments: toolArguments, in: contextProvider())
            }
        }
    }
}

/// Everything currently open: follow-up todos, per-student goals, and
/// observation notes flagged for follow-up.
///
/// Focus items have no evidence-pill kind, so like the album search tool
/// this one cites inline ([todo id=…], [focusItem id=…], [note id=…])
/// rather than feeding the evidence collector.
struct ListOpenFollowUpsTool: Tool {
    var contextProvider: MCPContextProvider = { ChatToolContext.context }
    let name = "listOpenFollowUps"
    let description = "List everything currently open: the guide's follow-up todos, each "
        + "student's open goals, and observation notes flagged for follow-up. Optionally "
        + "narrowed to one student."

    @Generable(description: "List open follow-ups arguments")
    struct Arguments {
        @Guide(description: "Only follow-ups concerning this student (first name, full name, "
            + "or nickname); empty for everyone")
        var studentName: String
    }

    func call(arguments: Arguments) async throws -> String {
        let toolArguments: [String: JSONValue] = ["student_name": .string(arguments.studentName)]
        let contextProvider = contextProvider
        return await MainActor.run {
            bridgedNotebookOperation {
                try MCPNotebookTools.listOpenFollowUps(arguments: toolArguments, in: contextProvider())
            }
        }
    }
}

#endif
