//
//  MCPNotebookTools+Library.swift
//  Maria's Notebook
//
//  The shelves either side of the teaching albums: the resource library
//  (printables, charts, forms) and the book club (packets, sessions, the
//  meetings inside them).
//
//  Both features store their PDFs outside Core Data — as security-scoped
//  bookmarks or relative paths — so these tools return what a guide needs to
//  find a file, never the file itself.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Resource Library

    static func listResourcesTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "list_resources",
            title: "List Resources",
            description: "The resource library: printables, charts, forms and guides the teacher "
                + "keeps on file, with their category, tags and size. The files themselves stay "
                + "on disk — this reports what exists and where it is filed.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "search": [
                        "type": "string",
                        "description": "Match against title, description, or tags"
                    ],
                    "category": [
                        "type": "string",
                        "description": "Only this category — Writing Papers, Math, Forms & Templates, and so on"
                    ],
                    "favorites_only": [
                        "type": "boolean",
                        "description": "Only resources marked favourite (default false)"
                    ],
                    "limit": [
                        "type": "integer",
                        "description": "Maximum resources to return, 1-100 (default 40)"
                    ]
                ]
            ],
            annotations: .readOnly,
            handler: { arguments in
                describeResources(arguments: arguments, in: context())
            }
        )
    }

    private static func describeResources(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) -> String {
        let search: String? = nonEmpty(arguments["search"]?.stringValue)?.lowercased()
        let category: String? = nonEmpty(arguments["category"]?.stringValue)?.lowercased()
        let favouritesOnly: Bool = arguments["favorites_only"]?.boolValue ?? false
        let limit: Int = intArgument(arguments, "limit", default: 40, range: 1...100)

        let all: [CDResource] = modelContext.safeFetch(CDFetchRequest(CDResource.self))
        var kept: [CDResource] = []
        for resource in all {
            if favouritesOnly && !resource.isFavorite { continue }
            if let category, resource.category.rawValue.lowercased() != category { continue }
            if let search, !resourceMatches(resource, search) { continue }
            kept.append(resource)
        }
        guard !kept.isEmpty else { return "No resources match that." }

        let sorted: [CDResource] = kept.sorted { lhs, rhs in
            let leftKey: String = lhs.category.rawValue
            let rightKey: String = rhs.category.rawValue
            if leftKey != rightKey { return leftKey < rightKey }
            return lhs.title < rhs.title
        }
        let shown: [CDResource] = Array(sorted.prefix(limit))
        let lines = shown.map { resource -> String in
            let id: String = resource.id?.uuidString ?? "unknown"
            var details: [String] = [resource.category.rawValue]
            if resource.isFavorite {
                details.append("favourite")
            }
            let tags: [String] = resource.tagsArray
            if !tags.isEmpty {
                details.append(tags.joined(separator: ", "))
            }
            if resource.fileSizeBytes > 0 {
                details.append(resource.fileSizeFormatted)
            }
            let summary: String = nonEmpty(resource.descriptionText).map { "\n    \($0)" } ?? ""
            return "- [resource id=\(id)] \(resource.title) (\(details.joined(separator: "; ")))\(summary)"
        }
        let more: String = sorted.count > shown.count
            ? "\n(\(sorted.count - shown.count) more not shown.)"
            : ""
        return "\(sorted.count) resource(s):\n" + lines.joined(separator: "\n") + more
    }

    private static func resourceMatches(_ resource: CDResource, _ needle: String) -> Bool {
        if resource.title.lowercased().contains(needle) { return true }
        if resource.descriptionText.lowercased().contains(needle) { return true }
        for tag in resource.tagsArray where tag.lowercased().contains(needle) {
            return true
        }
        return false
    }

    // MARK: - Book Club

    static func bookClubTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "book_club",
            title: "Book Club",
            description: "Book club sessions: what is being read, who is in the group, and every "
                + "meeting with its reading, leader, and whether it has happened.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "student_name": [
                        "type": "string",
                        "description": "Only sessions this student is in"
                    ],
                    "include_finished": [
                        "type": "boolean",
                        "description": "Also list sessions that have ended (default false)"
                    ]
                ]
            ],
            annotations: .readOnly,
            handler: { arguments in
                try describeBookClub(arguments: arguments, in: context())
            }
        )
    }

    private static func describeBookClub(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let student = try nonEmpty(arguments["student_name"]?.stringValue)
            .map { try resolveStudentReference($0, in: modelContext) }
        let includeFinished: Bool = arguments["include_finished"]?.boolValue ?? false
        let studentID: UUID? = student?.id

        let all: [CDBookClubSession] = modelContext.safeFetch(CDFetchRequest(CDBookClubSession.self))
        var kept: [CDBookClubSession] = []
        for session in all {
            if !includeFinished && session.status == .completed { continue }
            if let studentID, !session.studentIDs.contains(studentID) { continue }
            kept.append(session)
        }
        guard !kept.isEmpty else {
            let who = student.map { " for \($0.fullName)" } ?? ""
            return "No book club sessions\(who)."
        }

        let names = studentNameIndex(in: modelContext)
        let packets = packetTitles(in: modelContext)
        let sorted: [CDBookClubSession] = kept.sorted {
            ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast)
        }
        var lines: [String] = ["\(sorted.count) book club session(s):"]
        for session in sorted {
            lines.append(contentsOf: bookClubLines(session, names: names, packets: packets))
        }
        return lines.joined(separator: "\n")
    }

    private static func bookClubLines(
        _ session: CDBookClubSession, names: [String: String], packets: [UUID: String]
    ) -> [String] {
        let id: String = session.id?.uuidString ?? "unknown"
        var details: [String] = [session.status.rawValue]
        if let book = session.packetUUID.flatMap({ packets[$0] }) {
            details.append("reading \(book)")
        }
        let who: [String] = session.studentIDs.compactMap { names[$0.uuidString] }.sorted()
        details.append(who.isEmpty ? "no members" : who.joined(separator: ", "))
        if let start = session.startDate {
            details.append("from \(dayString(start))")
        }

        var lines: [String] = [
            "- [bookClubSession id=\(id)] \(session.displayTitle) (\(details.joined(separator: "; ")))"
        ]
        for meeting in session.orderedMeetings {
            let mark: String = meeting.isCompleted ? "●" : "○"
            let reading: String = nonEmpty(meeting.readingLabel).map { " — \($0)" } ?? ""
            let leader: String = nonEmpty(meeting.leaderStudentID)
                .flatMap { names[$0] }
                .map { " (led by \($0))" } ?? ""
            lines.append("    \(mark) \(dayString(meeting.date))\(reading)\(leader)")
        }
        return lines
    }

    private static func packetTitles(in modelContext: NSManagedObjectContext) -> [UUID: String] {
        let packets: [CDBookClubPacket] = modelContext
            .safeFetch(CDFetchRequest(CDBookClubPacket.self))
        return Dictionary(
            packets.compactMap { packet in packet.id.map { ($0, packet.title) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    // MARK: - Reminders

    static func listRemindersTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "list_reminders",
            title: "List Reminders",
            description: "The teacher's reminders, including any synced from Apple Reminders. "
                + "These are separate from todos — list_todos covers the notebook's own list.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "include_completed": [
                        "type": "boolean",
                        "description": "Also list completed reminders (default false)"
                    ],
                    "limit": [
                        "type": "integer",
                        "description": "Maximum reminders to return, 1-100 (default 40)"
                    ]
                ]
            ],
            annotations: .readOnly,
            handler: { arguments in
                describeReminders(arguments: arguments, in: context())
            }
        )
    }

    private static func describeReminders(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) -> String {
        let includeCompleted: Bool = arguments["include_completed"]?.boolValue ?? false
        let limit: Int = intArgument(arguments, "limit", default: 40, range: 1...100)

        let all: [CDReminder] = modelContext.safeFetch(CDFetchRequest(CDReminder.self))
        var kept: [CDReminder] = []
        for reminder in all where includeCompleted || !reminder.isCompleted {
            kept.append(reminder)
        }
        guard !kept.isEmpty else {
            return includeCompleted ? "No reminders." : "No open reminders."
        }

        let sorted: [CDReminder] = kept.sorted {
            ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
        }
        let shown: [CDReminder] = Array(sorted.prefix(limit))
        let lines = shown.map { reminder -> String in
            let id: String = reminder.id?.uuidString ?? "unknown"
            var details: [String] = []
            if let due = reminder.dueDate {
                details.append("due \(dayString(due))")
            }
            if reminder.isCompleted {
                details.append("done \(dayString(reminder.completedAt))")
            }
            if reminder.eventKitReminderID != nil {
                details.append("synced from Apple Reminders")
            }
            let suffix: String = details.isEmpty ? "" : " (\(details.joined(separator: "; ")))"
            let notes: String = nonEmpty(reminder.notes).map { "\n    \($0)" } ?? ""
            return "- [reminder id=\(id)] \(reminder.title)\(suffix)\(notes)"
        }
        let more: String = sorted.count > shown.count
            ? "\n(\(sorted.count - shown.count) more not shown.)"
            : ""
        return "\(sorted.count) reminder(s):\n" + lines.joined(separator: "\n") + more
    }

    // MARK: - Day Pad

    static func dayPadTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "day_pad",
            title: "Day Pad",
            description: "The teacher's scratch pad for a day — whatever they jotted down that "
                + "did not belong anywhere else. Reads one day, or writes/replaces it.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "date": [
                        "type": "string",
                        "description": "The day, YYYY-MM-DD (default today)"
                    ],
                    "body": [
                        "type": "string",
                        "description": .string("New text for that day. Replaces what is there — "
                            + "read it first if you mean to add to it. Omit to just read.")
                    ]
                ]
            ],
            annotations: .idempotentWrite,
            handler: { arguments in
                try dayPad(arguments: arguments, in: context())
            }
        )
    }

    private static func dayPad(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let day: Date = AppCalendar.startOfDay(try dayArgument(arguments, "date") ?? Date())
        let request = CDFetchRequest(CDDayPad.self)
        request.predicate = NSPredicate(format: "day == %@", day as NSDate)
        request.fetchLimit = 1
        let existing: CDDayPad? = modelContext.safeFetch(request).first

        guard let body = arguments["body"]?.stringValue else {
            guard let text = existing.flatMap({ nonEmpty($0.body) }) else {
                return "The pad for \(dayString(day)) is empty."
            }
            return "Day pad for \(dayString(day)):\n\(text)"
        }

        let pad: CDDayPad = existing ?? {
            let created = CDDayPad(context: modelContext)
            created.id = UUID()
            created.day = day
            created.createdAt = Date()
            return created
        }()
        pad.body = body
        pad.modifiedAt = Date()

        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The day pad could not be saved.")
        }
        let verb: String = existing == nil ? "Wrote" : "Replaced"
        return "\(verb) the day pad for \(dayString(day))."
    }
}
