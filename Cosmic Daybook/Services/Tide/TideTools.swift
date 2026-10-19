// TideTools.swift
// The four Tide tools the sync calls, with their replies as values.

import Foundation

/// One action as Tide's reads and writes return it (`MCPQueue.ActionRow`,
/// read 2026-10-18). Only what the sync uses is decoded.
nonisolated struct TideAction: Decodable, Equatable, Sendable {
    /// Its words, as the write tools take them to name it.
    let action: String
    let note: String?
    /// The list's workspace path.
    let file: String?
    /// The innermost heading it sits under.
    let heading: String?
    /// The action this one is a part of, for a part.
    let partOf: String?
    /// Where it sits in its section, from 1, and how many rows the section has.
    let position: Int
    let of: Int
    /// open, waiting, someday, done or dropped.
    let state: String
    /// YYYY-MM-DD.
    let due: String?
    /// Sent by every reply except `list_actions`.
    let link: String?
    /// Its list's revision, which a positioned write needs.
    let revision: String

    private enum CodingKeys: String, CodingKey {
        case action, note, file, heading, position, of, state, due, link, revision
        case partOf = "part_of"
    }

    init(
        action: String, note: String? = nil, file: String?, heading: String? = nil, partOf: String? = nil,
        position: Int, of: Int, state: String = "open", due: String? = nil, link: String? = nil, revision: String
    ) {
        self.action = action
        self.note = note
        self.file = file
        self.heading = heading
        self.partOf = partOf
        self.position = position
        self.of = of
        self.state = state
        self.due = due
        self.link = link
        self.revision = revision
    }

    /// Not ticked, not dropped: open, waiting on someone or parked someday.
    var isUnfinished: Bool { ["open", "waiting", "someday"].contains(state) }
    var isOpen: Bool { state == "open" }

    /// This read's name for the row: two actions with the same words in one
    /// list share an address, so the sync tells them apart by where they sit.
    var key: String { "\(file ?? "")\u{1F}\(heading ?? "")\u{1F}\(position)\u{1F}\(action)" }

    /// Its address, made the way Tide makes it when the reply leaves it out.
    var actionLink: TideActionLink? {
        if let link, let parsed = TideActionLink(link) { return parsed }
        return file.map { TideActionLink(file: $0, text: action) }
    }

    /// The notebook to-do it was sent from, if it was.
    var notebookID: UUID? { TideNotebookMarker.todoID(in: note) }
}

/// One list under an area (`QueueFileJSON`).
nonisolated struct TideList: Decodable, Equatable, Sendable {
    let file: String
    /// Whether it feeds Tide's Next Actions; only those lists' rows come back
    /// from `get_area`.
    let feeds: Bool
    let open: Int

    var name: String { TideActionLink.listName(ofFile: file) }
}

/// `get_area`'s reply: the area's lists, and every unfinished action of the
/// lists that feed (`AreaJSON`, `MCPQueue.getArea`).
nonisolated struct TideArea: Decodable, Equatable, Sendable {
    let dir: String
    let name: String
    let boxes: [TideAction]?
    let queueFiles: [TideList]?

    private enum CodingKeys: String, CodingKey {
        case dir, name, boxes
        case queueFiles = "queue_files"
    }

    init(dir: String, name: String, boxes: [TideAction]?, queueFiles: [TideList]?) {
        self.dir = dir
        self.name = name
        self.boxes = boxes
        self.queueFiles = queueFiles
    }

    /// The lists whose actions this reply carries.
    var feedingLists: [TideList] { (queueFiles ?? []).filter(\.feeds) }

    /// The headings of `file`, in the order its actions come.
    func headings(of file: String) -> [String] {
        var seen = Set<String>()
        var headings: [String] = []
        for row in boxes ?? [] where row.file == file && row.partOf == nil {
            guard let heading = row.heading, seen.insert(heading.lowercased()).inserted else { continue }
            headings.append(heading)
        }
        return headings
    }
}

/// A write's reply (`WriteReport`): the action as the list now holds it, what
/// a tick did, and the list's new revision.
nonisolated struct TideWriteReply: Decodable, Equatable, Sendable {
    let ok: Bool
    let action: TideAction?
    /// For a tick: completed, rolled (a repeat moved on), routine_rolled or
    /// already_closed.
    let outcome: String?
    let revision: String
}

/// Why a Tide tool said no.
nonisolated enum TideToolError: Error, Equatable {
    /// Tide's refusal, one rule and fix per finding (`MCPRefusal`).
    case refused([Refusal])
    /// Tide's plain error sentence (`MCPErrorShape.plainJSON`).
    case failed(String)
    /// A reply the sync couldn't read; for the log and Details only.
    case unreadable(String)

    struct Refusal: Decodable, Equatable, Sendable {
        let rule: String
        let fix: String
    }

    /// The list changed since the read the position came from: read again,
    /// never retry the same write.
    var isStaleRevision: Bool {
        guard case .refused(let refusals) = self else { return false }
        return refusals.contains { $0.rule.contains("has changed since it was read") }
    }

    /// Tide can't tell which action the words name: its list has more than
    /// one with them, ticked ones included (`MCPQueue.namedAction`). Tide
    /// names an action by position only for `delete_action`, so a tick or a
    /// note on one of them can't be aimed.
    var isAmbiguous: Bool {
        guard case .refused(let refusals) = self else { return false }
        return refusals.contains { $0.rule.contains("matches more than one action") }
    }

    /// The saved heading isn't in the list (`StoreTools.noHeading`).
    var isMissingHeading: Bool {
        guard case .refused(let refusals) = self else { return false }
        return refusals.contains { $0.rule.hasPrefix("no heading") }
    }

    /// A refusal that passes by itself: the action isn't in Tide's store yet,
    /// or Tide is still opening. Asked again next run, never given up on.
    var isTemporary: Bool {
        if isStillOpening { return true }
        guard case .refused(let refusals) = self else { return false }
        return refusals.contains { $0.rule.contains("isn't in Tide's store yet") }
    }

    /// Tide is still opening its store and answers nothing yet.
    var isStillOpening: Bool {
        guard case .failed(let message) = self else { return false }
        return message.contains("still opening") || message.contains("still reading")
    }

    /// The words for the Details disclosure.
    var details: String {
        switch self {
        case .refused(let refusals): refusals.map { "\($0.rule) — \($0.fix)" }.joined(separator: "\n")
        case .failed(let message): message
        case .unreadable(let detail): detail
        }
    }
}

/// The Tide tools the sync calls, named and shaped as Tide's server declares
/// them (`TideCore/MCPToolSpec.swift`, read 2026-10-18). Never
/// `changes_since`: a call without an author or device filter moves the one
/// cursor Danny's Claude sessions read "what changed since you last asked"
/// from (`StoreTools+Changes.swift`), so the sync compares snapshots instead.
struct TideTools {
    let transport: TideTransport

    /// Every list of an area and every unfinished action in the ones that feed.
    func area(_ dir: String) async throws -> TideArea {
        try await call("get_area", ["dir": .string(dir)], as: TideArea.self)
    }

    /// One action to add, and where (`add_action`'s arguments).
    struct NewAction: Equatable {
        let file: String
        let heading: String?
        let action: String
        let note: String?
        /// From the read that decided them; left off only for a list with no actions.
        let position: Int?
        let revision: String?
        /// YYYY-MM-DD, today or later (Tide refuses a due date already past).
        let due: String?
        /// YYYY-MM-DD: a to-do planned for a later day waits in Tide until then.
        let start: String?
    }

    /// Adds one action.
    func addAction(_ new: NewAction) async throws -> TideWriteReply {
        var arguments: [String: JSONValue] = ["file": .string(new.file), "action": .string(new.action)]
        if let heading = new.heading { arguments["heading"] = .string(heading) }
        if let note = new.note, !note.isEmpty { arguments["note"] = .string(note) }
        if let position = new.position { arguments["position"] = .int(position) }
        if let revision = new.revision { arguments["revision"] = .string(revision) }
        if let due = new.due { arguments["due"] = .string(due) }
        if let start = new.start { arguments["start"] = .string(start) }
        return try await call("add_action", arguments, as: TideWriteReply.self)
    }

    /// Replaces the note of the action with these words in `file`, and
    /// nothing else. Tide refuses a note that loses any of Danny's own
    /// paragraphs, checked against the note as it is when the write lands.
    func updateNote(file: String, action: String, note: String) async throws -> TideWriteReply {
        let arguments: [String: JSONValue] = ["file": .string(file), "action": .string(action), "note": .string(note)]
        return try await call("update_action", arguments, as: TideWriteReply.self)
    }

    /// Ticks the action with these words in `file`.
    func completeAction(file: String, action: String) async throws -> TideWriteReply {
        try await call("complete_action", ["file": .string(file), "action": .string(action)], as: TideWriteReply.self)
    }

    /// The actions of one list in one state, every file whether it feeds or not.
    func actions(inFile file: String, state: String, limit: Int) async throws -> [TideAction] {
        let arguments: [String: JSONValue] = [
            "file": .string(file), "state": .string(state), "feeds": .bool(false), "limit": .int(limit)
        ]
        let reply = try await transport.callTool("list_actions", arguments: arguments)
        try Self.throwIfRefused(reply)
        // The array may end with a {truncated, shown, of, fix} note, which isn't a row.
        guard let items = try? JSONDecoder().decode([JSONValue].self, from: Data(reply.text.utf8)) else {
            throw TideToolError.unreadable("list_actions reply wasn't an array")
        }
        return items.compactMap { item in
            guard item.objectValue?["truncated"] == nil,
                  let data = try? JSONEncoder().encode(item) else { return nil }
            return try? JSONDecoder().decode(TideAction.self, from: data)
        }
    }

    private func call<T: Decodable>(
        _ name: String, _ arguments: [String: JSONValue], as type: T.Type
    ) async throws -> T {
        let reply = try await transport.callTool(name, arguments: arguments)
        try Self.throwIfRefused(reply)
        do {
            return try JSONDecoder().decode(T.self, from: Data(reply.text.utf8))
        } catch {
            throw TideToolError.unreadable("\(name) reply didn't decode")
        }
    }

    /// Tide's `{"ok": false, "refused": [...]}` or `{"ok": false, "error": "..."}`.
    private static func throwIfRefused(_ reply: TideToolReply) throws {
        guard reply.isError else { return }
        struct Refusal: Decodable {
            let refused: [TideToolError.Refusal]?
            let error: String?
        }
        let decoded = try? JSONDecoder().decode(Refusal.self, from: Data(reply.text.utf8))
        if let refused = decoded?.refused, !refused.isEmpty { throw TideToolError.refused(refused) }
        throw TideToolError.failed(decoded?.error ?? reply.text)
    }
}
