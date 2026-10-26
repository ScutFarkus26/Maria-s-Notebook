//
//  MCPNotebookTools+LessonAttachments.swift
//  Cosmic Daybook
//
//  Attaching a file on this Mac to a lesson: Claude names a remade album PDF
//  by its path, and the lesson's Files card gets a copy (plan "Lesson file
//  attachments", Decisions 6 and 7). Every change goes through
//  `LessonAttachmentService`, the Files card's own writer, including its file
//  checks; the path is checked first against the folders the guide granted
//  (`MCPAttachFolders`). Listing and removing are in +LessonAttachmentReads.
//
//  Not wrapped in `undoingOnFailure`: the service undoes exactly its own
//  change when a save fails, with a transaction of its own, and the two don't
//  nest; a replace also waits for the old file, which a scope can't span.
//

import CoreData
import Foundation

/// What the lesson-file tools reach outside the notebook: the folders a path
/// may come from, and the Lesson Files folder copies go into. Tests pass
/// scratch ones.
struct MCPLessonFiles: Sendable {
    var folders: MCPAttachFolders.Access
    var storage: ManagedPDFFileStorage
    /// Where files nothing uses any more go; nil is the Trash.
    var trash: (@Sendable ([URL]) -> Void)?

    static let live = MCPLessonFiles(folders: .live, storage: LessonFileStorage.storage, trash: nil)

    /// The Files card's writer over `context`. MCP always works on the real
    /// notebook, never the Sample Class.
    func service(for context: NSManagedObjectContext) -> LessonAttachmentService {
        LessonAttachmentService(context: context, storage: storage, trash: trash)
    }
}

extension MCPNotebookTools {

    // MARK: - Attach File to Lesson

    static func attachFileToLessonTool(
        context: @escaping MCPContextProvider, files: MCPLessonFiles
    ) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "attach_file_to_lesson",
            title: "Attach File to Lesson",
            description: "Attach a PDF or an image on this Mac to a lesson's Files card. The file is "
                + "copied into the lesson (it reaches the guide's other devices through iCloud Drive) "
                + "and the original stays where it is. The path must be inside a folder the guide "
                + "granted in Settings › Claude Desktop, or one of her album folders. A lesson file "
                + "with the same title is refused unless replace_existing is true, which gives that "
                + "same file (same id) the new contents; identical contents change nothing. The "
                + "receipt cites [lessonAttachment id=<uuid>]; list_lesson_attachments shows the files.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "lesson": [
                        "type": "string",
                        "description": "Lesson id (from find_lessons or list_lessons_by_area) or exact name"
                    ],
                    "path": [
                        "type": "string",
                        "description": "The file's full path, starting with / or ~/"
                    ],
                    "title": [
                        "type": "string",
                        "description": .string("The name the lesson shows for the file, kept as written. "
                            + "Default: the file's name without its extension")
                    ],
                    "source_note": [
                        "type": "string",
                        "description": .string("Where the file came from, shown with it. On a replace, "
                            + "omit it to keep the old note; an empty string clears it")
                    ],
                    "replace_existing": [
                        "type": "boolean",
                        "description": .string("Replace the lesson's file with the same title instead of "
                            + "refusing (default false)")
                    ]
                ],
                "required": ["lesson", "path"]
            ],
            annotations: .idempotentWrite,
            handler: { arguments in
                try await attachFileToLesson(arguments: arguments, in: context(), files: files)
            }
        )
    }

    private static func attachFileToLesson(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext, files: MCPLessonFiles
    ) async throws -> String {
        let lesson = try resolveLessonReference(try requireString(arguments, "lesson"), in: modelContext)
        let path = try requireString(arguments, "path")
        let title = nonEmpty(arguments["title"]?.stringValue) ?? sourceStem(of: path)
        let sourceNote = arguments["source_note"]?.stringValue
        let replaceExisting = arguments["replace_existing"]?.boolValue ?? false
        let service = files.service(for: modelContext)

        return try await files.folders.withReadAccess(to: path) { file in
            do {
                // The file is checked before the title, so a refusal is about the file.
                _ = try LessonAttachmentService.validate(fileAt: file, allowedTypes: LessonAttachmentService.pdfOrImage)
                if let existing = service.existingAttachment(titled: title, on: lesson) {
                    guard replaceExisting else {
                        throw MCPToolError(sameTitleRefusal(existing, on: lesson))
                    }
                    let outcome = try await service.replace(
                        existing, withFileAt: file, notes: sourceNote, allowedTypes: LessonAttachmentService.pdfOrImage
                    )
                    return replaceReceipt(outcome, existing, on: lesson)
                }
                let attachment = try service.add(
                    fileAt: file, to: lesson, scope: .lesson, title: title, notes: sourceNote ?? "",
                    allowedTypes: LessonAttachmentService.pdfOrImage
                )
                return "Attached \(describeFile(attachment)) to \(describeLesson(lesson)) \(cite(attachment))."
            } catch let problem as LessonAttachmentService.Problem {
                throw MCPToolError(problem.errorDescription ?? "Couldn't attach the file. Try again.")
            }
        }
    }

    /// The file's name without its extension: "circle-area-of-a-circle" for
    /// ".../circle-area-of-a-circle.pdf".
    static func sourceStem(of path: String) -> String {
        let name = (path.trimmed() as NSString).lastPathComponent
        let stem = (name as NSString).deletingPathExtension
        return stem.isEmpty ? name : stem
    }

    private static func sameTitleRefusal(_ existing: CDLessonAttachment, on lesson: CDLesson) -> String {
        "\(describeLesson(lesson)) already has a file titled '\(existing.title)' \(cite(existing)) "
            + "(\(existing.fileType.uppercased()), \(existing.fileSizeFormatted), added "
            + "\(dayString(existing.attachedAt))). Nothing was attached. Pass replace_existing: true to give "
            + "that file this one's contents, or a different title to attach it as another file."
    }

    /// The receipt for a replace, from the record as saved. A call that
    /// changed nothing says so and is left out of the write journal.
    private static func replaceReceipt(
        _ outcome: LessonAttachmentService.ReplaceOutcome, _ attachment: CDLessonAttachment, on lesson: CDLesson
    ) -> String {
        switch outcome {
        case .replaced:
            return "Replaced \(describeFile(attachment)) on \(describeLesson(lesson)) \(cite(attachment))."
        case .noteChanged:
            return "Updated the note on \(describeFile(attachment)) on \(describeLesson(lesson)) "
                + "\(cite(attachment)); its contents were already the same as that file's."
        case .unchanged:
            MCPCallOutcome.markNothingWritten()
            return "Already up to date: \(describeFile(attachment)) on \(describeLesson(lesson)) "
                + "\(cite(attachment)) has the same contents as that file. Nothing changed."
        }
    }

    // MARK: - Describing a file

    /// "'Area of a Circle — remade album pages' (PDF, 606 KB)": the stored
    /// title and size, never the arguments.
    static func describeFile(_ attachment: CDLessonAttachment) -> String {
        "'\(attachment.title)' (\(attachment.fileType.uppercased()), \(attachment.fileSizeFormatted))"
    }

    static func cite(_ attachment: CDLessonAttachment) -> String {
        "[lessonAttachment id=\(attachment.id?.uuidString ?? "unknown")]"
    }
}
