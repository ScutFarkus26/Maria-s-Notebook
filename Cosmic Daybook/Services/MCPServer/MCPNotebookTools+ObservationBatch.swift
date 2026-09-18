//
//  MCPNotebookTools+ObservationBatch.swift
//  Cosmic Daybook
//
//  Two things the observation and follow-up writers share.
//
//  First, the duplicate guards. A model that loses its place — a retried
//  call, a re-read transcript — files the same observation twice, and the
//  guide finds two identical notes in the inbox. So both writers look for a
//  record already carrying the identical text, the identical children and
//  the same day, and report it rather than adding another. The guard only
//  ever reads: it never edits or deletes what it finds, and `force: true`
//  files the second copy when the guide really does mean two.
//
//  Second, the batch form of create_observation. Every name and date is
//  resolved before the first insert, so a typo in the fourth item fails the
//  call with nothing written rather than leaving three notes behind.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Duplicate Guards

    /// The student identity two records are compared on: `nil` for a
    /// whole-class note, otherwise the set of children named. Order and
    /// storage shape (`.student` vs a one-element `.students`) don't matter.
    static func scopeIdentity(_ scope: NoteScope) -> Set<UUID>? {
        switch scope {
        case .all: return nil
        case .student(let id): return [id]
        case .students(let ids): return Set(ids)
        }
    }

    /// An observation already filed with this exact body, scope and day, if
    /// one exists. Read-only — the caller decides what to do about it.
    static func existingObservation(
        body: String, scope: NoteScope, on day: Date,
        in modelContext: NSManagedObjectContext
    ) -> CDNote? {
        let range = AppCalendar.dayRange(for: day)
        let request = CDFetchRequest(CDNote.self)
        request.predicate = NSPredicate(
            format: "createdAt >= %@ AND createdAt < %@",
            range.start as NSDate, range.end as NSDate
        )
        let wanted = body.trimmed()
        let identity = scopeIdentity(scope)
        return modelContext.safeFetch(request).first { note in
            note.body.trimmed() == wanted && scopeIdentity(note.scope) == identity
        }
    }

    /// An open follow-up already carrying this exact title, student set and
    /// day, if one exists. A completed todo is not a duplicate: the guide
    /// finished that one and is asking for the next.
    static func existingFollowUp(
        title: String, studentIDs: [UUID], on day: Date,
        in modelContext: NSManagedObjectContext
    ) -> CDTodoItem? {
        let range = AppCalendar.dayRange(for: day)
        let request = CDFetchRequest(CDTodoItem.self)
        request.predicate = NSPredicate(
            format: "isCompleted == NO AND createdAt >= %@ AND createdAt < %@",
            range.start as NSDate, range.end as NSDate
        )
        let wanted = title.trimmed()
        let identity = Set(studentIDs.map(\.uuidString))
        return modelContext.safeFetch(request).first { todo in
            todo.title.trimmed() == wanted && Set(todo.studentIDsArray) == identity
        }
    }

    /// The refusal both guards return: what already exists, and how to file
    /// a second copy anyway.
    static func duplicateNotice(subject: String, citation: String, on day: Date) -> String {
        "An identical \(subject) from \(dayString(day)) already exists \(citation). "
            + "Nothing was filed — pass force: true to file another."
    }

    /// `add_follow_up`'s side of the guard, kept here so both writers read the
    /// same wording. Returns nil when there is nothing in the way.
    static func duplicateFollowUpNotice(
        title: String, studentIDs: [UUID], force: Bool,
        in modelContext: NSManagedObjectContext
    ) -> String? {
        guard !force else { return nil }
        let today = Date()
        guard let existing = existingFollowUp(
            title: title, studentIDs: studentIDs, on: today, in: modelContext
        ) else { return nil }
        return duplicateNotice(
            subject: "follow-up", citation: "[todo id=\(citationID(existing.id))]", on: today
        )
    }

    /// A uuid as tools cite it, with the same fallback every other tool uses.
    static func citationID(_ id: UUID?) -> String { id?.uuidString ?? "unknown" }

    // MARK: - Resolved Observations

    /// One item of a `create_observation` call with every name and date
    /// already settled — built for the whole call before anything is written.
    struct ObservationDraft {
        let students: [CDStudent]
        let studentIDs: [UUID]
        let body: String
        let date: Date
        let tags: [String]
        let needsFollowUp: Bool

        var scope: NoteScope {
            studentIDs.count == 1
                ? .student(studentIDs[0])
                : .students(studentIDs.sorted { $0.uuidString < $1.uuidString })
        }

        var names: String { students.map(\.fullName).joined(separator: ", ") }
    }

    /// Resolves one observation's arguments — the single form's whole body,
    /// and one item of the batch form.
    static func observationDraft(
        from arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> ObservationDraft {
        let body = try requireString(arguments, "body")
        let names = stringArrayArgument(arguments, "student_names")
        guard !names.isEmpty else {
            throw MCPToolError("At least one student name is required.")
        }
        let students = try names.map { try resolveStudent(named: $0, in: modelContext) }
        let studentIDs = students.compactMap(\.id)
        guard studentIDs.count == students.count else {
            throw MCPToolError("A matched student record has no identifier.")
        }
        return ObservationDraft(
            students: students,
            studentIDs: studentIDs,
            body: body,
            date: try dayArgument(arguments, "date") ?? Date(),
            tags: stringArrayArgument(arguments, "tags"),
            needsFollowUp: arguments["needs_follow_up"]?.boolValue ?? false
        )
    }

    /// Resolves every item of a `notes` array. A failure names the item that
    /// failed — its index and the opening of its body — so the guide can see
    /// which observation to fix, and nothing at all is written.
    static func observationDrafts(
        fromBatch entries: [JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> [ObservationDraft] {
        guard !entries.isEmpty else {
            throw MCPToolError("notes was empty — pass at least one observation.")
        }
        return try entries.enumerated().map { index, entry in
            guard let item = entry.objectValue else {
                throw MCPToolError(
                    "notes[\(index)] must be an object with student_names and body."
                )
            }
            do {
                return try observationDraft(from: item, in: modelContext)
            } catch let error as MCPToolError {
                throw MCPToolError("notes[\(index)] (\(bodyPrefix(of: item))): \(error.message)")
            }
        }
    }

    private static func bodyPrefix(of item: [String: JSONValue]) -> String {
        let body = item["body"]?.stringValue?.trimmed() ?? ""
        guard !body.isEmpty else { return "no body" }
        return body.count <= 40 ? "\"\(body)\"" : "\"\(body.prefix(40))…\""
    }

    /// Builds the note the way `LogObservationIntent` does. The caller saves.
    static func insertObservation(
        _ draft: ObservationDraft, in modelContext: NSManagedObjectContext
    ) -> CDNote {
        let note = CDNote(context: modelContext)
        note.createdAt = draft.date
        note.body = draft.body
        note.scope = draft.scope
        if !draft.tags.isEmpty {
            note.tagsArray = draft.tags
        }
        note.needsFollowUp = draft.needsFollowUp
        note.syncStudentLinks(in: modelContext)
        return note
    }

    /// Writes a resolved batch: one line per item, one save at the end. A
    /// duplicate item is reported and skipped rather than failing the call —
    /// the other observations in the batch are still the guide's to file.
    static func recordObservationBatch(
        _ drafts: [ObservationDraft], force: Bool, in modelContext: NSManagedObjectContext
    ) throws -> String {
        var lines: [String] = []
        var filed = 0
        var skipped = 0
        for draft in drafts {
            if !force, let existing = existingObservation(
                body: draft.body, scope: draft.scope, on: draft.date, in: modelContext
            ) {
                skipped += 1
                lines.append("- Skipped: identical note exists [note id=\(citationID(existing.id))]")
                continue
            }
            let note = insertObservation(draft, in: modelContext)
            filed += 1
            lines.append(
                "- Filed [note id=\(citationID(note.id))] for \(draft.names) "
                    + "on \(dayString(draft.date))"
            )
        }
        if filed > 0, !modelContext.safeSave() {
            modelContext.rollback()
            throw MCPToolError("The observations could not be saved.")
        }
        let header = "Filed \(filed) observation(s)"
            + (skipped > 0 ? ", skipped \(skipped) duplicate(s)" : "") + ":"
        return ([header] + lines).joined(separator: "\n")
    }

    // MARK: - Schema

    /// The fields one observation takes, shared by the single form and each
    /// item of the batch form so the two can never drift apart.
    private static let observationFields: [String: JSONValue] = [
        "student_names": [
            "type": "array",
            "items": ["type": "string"],
            "minItems": 1,
            "description": "First names, full names, or nicknames of the students observed"
        ],
        "body": [
            "type": "string",
            "description": "The observation text, as the teacher phrased it"
        ],
        "date": [
            "type": "string",
            "description": "The day observed, YYYY-MM-DD (default today)"
        ],
        "tags": [
            "type": "array",
            "items": ["type": "string"],
            "description": "Optional tags to file the note under"
        ],
        "needs_follow_up": [
            "type": "boolean",
            "description": "Flag the note for the follow-up inbox (default false)"
        ]
    ]

    /// The single form's fields, plus the batch array and the guard override.
    /// Nothing is required at the top level: `body` and `student_names` are
    /// required of each *observation*, whichever form carries it, and that is
    /// checked where the arguments are resolved.
    static let createObservationSchema: JSONValue = {
        var properties: [String: JSONValue] = observationFields
        properties["notes"] = [
            "type": "array",
            "description": .string("Several observations in one call. Each item takes the "
                + "same fields as the single form; when it is given, student_names and "
                + "body are not needed at the top level."),
            "items": [
                "type": "object",
                "properties": JSONValue.object(observationFields).withoutDescriptions,
                "required": ["student_names", "body"]
            ]
        ]
        properties["force"] = [
            "type": "boolean",
            "description": .string("File the note even though an identical one already "
                + "exists from that day (default false). Applies to every item of a batch.")
        ]
        return .object(["type": "object", "properties": .object(properties)])
    }()
}
