//
//  MCPNotebookTools+LessonAttachmentReads.swift
//  Cosmic Daybook
//
//  A lesson's files over MCP: listing them, removing one (two-step, as the
//  destructive tools are), and the " · files: …" suffix `find_lessons` and
//  `list_lessons_by_area` put on a lesson that holds files of its own (plan
//  "Lesson file attachments", Decision 7). `describeLesson` itself is
//  unchanged, so other tools' receipts read as they did.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - List Lesson Attachments

    static func listLessonAttachmentsTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "list_lesson_attachments",
            title: "List Lesson Attachments",
            description: "The files on a lesson's Files card: its own, then those shared with its whole "
                + "sequence or area from another lesson. Each line is [lessonAttachment id=<uuid>] with "
                + "its title, scope, type, size, the days it was added and last changed, and its source "
                + "note.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "lesson": ["type": "string", "description": "Lesson id or exact name"]
                ],
                "required": ["lesson"]
            ],
            annotations: .readOnly,
            handler: { arguments in
                let modelContext = context()
                let lesson = try resolveLessonReference(try requireString(arguments, "lesson"), in: modelContext)
                return listLessonAttachments(of: lesson)
            }
        )
    }

    private static func listLessonAttachments(of lesson: CDLesson) -> String {
        let attachments = LessonFileStorage.getAttachments(forLesson: lesson, includeInherited: true)
        guard !attachments.isEmpty else {
            return "\(describeLesson(lesson)) has no files."
        }
        let order: [AttachmentScope] = [.lesson, .sequence, .area]
        let sorted = attachments.sorted { lhs, rhs in
            let left = order.firstIndex(of: lhs.scope) ?? 0
            let right = order.firstIndex(of: rhs.scope) ?? 0
            if left != right { return left < right }
            return (lhs.attachedAt ?? .distantPast) > (rhs.attachedAt ?? .distantPast)
        }
        let lines = sorted.map { "- " + describeListed($0, on: lesson) }
        return "\(describeLesson(lesson)): \(attachments.count) file(s)\n" + lines.joined(separator: "\n")
    }

    private static func describeListed(_ attachment: CDLessonAttachment, on lesson: CDLesson) -> String {
        var parts: [String] = [
            "\(cite(attachment)) '\(attachment.title)'",
            scopeLabel(attachment, on: lesson),
            attachment.fileType.uppercased(),
            attachment.fileSizeFormatted,
            "added \(dayString(attachment.attachedAt))",
            "changed \(dayString(attachment.lastChanged))"
        ]
        if attachment.id != nil, lesson.primaryAttachmentIDUUID == attachment.id {
            parts.append("the lesson's primary file")
        }
        let note = attachment.notes.trimmed()
        if !note.isEmpty { parts.append("source: \(note)") }
        return parts.joined(separator: " · ")
    }

    private static func scopeLabel(_ attachment: CDLessonAttachment, on lesson: CDLesson) -> String {
        let holder = attachment.lesson.flatMap { $0 == lesson ? nil : $0 }
        let from = holder.map { " (from \(describeLesson($0)))" } ?? ""
        switch attachment.scope {
        case .lesson: return "this lesson"
        case .sequence: return "whole sequence" + from
        case .area: return "whole area" + from
        }
    }

    // MARK: - Remove Lesson Attachment

    static func removeLessonAttachmentTool(
        context: @escaping MCPContextProvider, files: MCPLessonFiles
    ) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "remove_lesson_attachment",
            title: "Remove Lesson Attachment",
            description: "Remove one file from a lesson, by its id from list_lesson_attachments. Called "
                + "without confirm it only reports what would go, and changes nothing; call it again with "
                + "confirm: true to remove it. The file goes to the Trash unless another lesson file uses "
                + "it. A sequence- or area-wide file leaves every lesson it reaches.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "attachment": [
                        "type": "string",
                        "description": "The file's id, from list_lesson_attachments or attach_file_to_lesson"
                    ],
                    "confirm": [
                        "type": "boolean",
                        "description": "Pass true, after reading the report, to remove it"
                    ]
                ],
                "required": ["attachment"]
            ],
            annotations: .destructive,
            handler: { arguments in
                try removeLessonAttachment(arguments: arguments, in: context(), files: files)
            }
        )
    }

    private static func removeLessonAttachment(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext, files: MCPLessonFiles
    ) throws -> String {
        let reference = try requireString(arguments, "attachment")
        guard let id = UUID(uuidString: reference) else {
            throw MCPToolError("\"\(reference)\" isn't a file id. Pass the id list_lesson_attachments shows.")
        }
        guard let attachment = modelContext.object(CDLessonAttachment.self, id: id), !attachment.isDeleted else {
            throw MCPToolError("No lesson file with id \(reference) was found.")
        }
        guard arguments["confirm"]?.boolValue == true else {
            MCPCallOutcome.markNothingWritten()
            return "remove_lesson_attachment refused — nothing has been changed.\n"
                + "Re-call with confirm: true to proceed.\n\n" + describeRemoval(of: attachment, done: false)
        }
        // Worded before the record goes.
        let receipt = describeRemoval(of: attachment, done: true)
        do {
            try files.service(for: modelContext).remove(attachment)
        } catch let problem as LessonAttachmentService.Problem {
            throw MCPToolError(problem.errorDescription ?? "Couldn't remove the file. Try again.")
        }
        return receipt
    }

    /// What a removal takes away: before it happens (`done` false) or as done.
    private static func describeRemoval(of attachment: CDLessonAttachment, done: Bool) -> String {
        let from = attachment.lesson.map(describeLesson) ?? "no lesson"
        var lines = ["\(done ? "Removed" : "Removing") \(describeFile(attachment)) \(cite(attachment)) from \(from)."]
        switch attachment.scope {
        case .lesson: break
        case .sequence:
            lines.append("It is shared with every lesson in that sequence: removing it takes it off all of them.")
        case .area:
            lines.append("It is shared with every lesson in that area: removing it takes it off all of them.")
        }
        if let lesson = attachment.lesson, attachment.id != nil, lesson.primaryAttachmentIDUUID == attachment.id {
            lines.append("It is the lesson's primary file: removing it leaves the lesson with none.")
        }
        lines.append("Its file goes to the Trash unless another lesson file uses it.")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Files suffix for lesson lists

/// The titles of each lesson's own files, read with one fetch for a whole
/// list (`list_lessons_by_area` has no cap). Only lesson-scope files count: a
/// sequence-wide file would otherwise mark every lesson in the sequence.
struct LessonFileTitles {
    /// Titles shown before "+N more".
    static let shownTitles = 3

    private let titles: [NSManagedObjectID: [String]]

    init(in modelContext: NSManagedObjectContext) {
        let request = CDFetchRequest(CDLessonAttachment.self)
        request.predicate = NSPredicate(format: "lesson != nil")
        request.returnsObjectsAsFaults = false
        var byLesson: [NSManagedObjectID: [(title: String, added: Date)]] = [:]
        for attachment in modelContext.safeFetch(request) where !attachment.isDeleted && attachment.scope == .lesson {
            // The relationship's object id, without reading the lesson.
            guard let lessonID = attachment.lesson?.objectID else { continue }
            byLesson[lessonID, default: []].append((attachment.title, attachment.attachedAt ?? .distantPast))
        }
        titles = byLesson.mapValues { files in files.sorted { $0.added > $1.added }.map(\.title) }
    }

    /// " · files: A, B, C, +2 more", or "" for a lesson with no files of its own.
    func suffix(for lesson: CDLesson) -> String {
        guard let names = titles[lesson.objectID], !names.isEmpty else { return "" }
        var shown = names.prefix(Self.shownTitles).map { "'\($0)'" }
        if names.count > Self.shownTitles { shown.append("+\(names.count - Self.shownTitles) more") }
        return " · files: " + shown.joined(separator: ", ")
    }
}
