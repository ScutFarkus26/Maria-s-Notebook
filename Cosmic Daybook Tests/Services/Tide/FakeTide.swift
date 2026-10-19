import Foundation
@testable import CosmicDaybook

/// A stand-in for Tide's server, in memory: the four tools the sync calls,
/// answering in the shapes Tide's own handlers do (`StoreTools+Actions`,
/// `MCPQueue+Areas`, `MCPQueue+ListActions`, read 2026-10-18), with Tide's
/// position and revision rules. Tests never reach the real server: a
/// simulator's `localhost` is Danny's live Tide.
final class FakeTide: TideTransport {
    struct Action {
        var text: String
        var note: String?
        var file: String
        var heading: String?
        var state = "open"
        var due: String?
        var start: String?
        var repeats = false
    }

    static let area = TideSyncSettings.area
    static let upperEl = TideSyncSettings.defaultDestination
    static let roomSetup = "Areas/My Classrooms/Room Setup/To do.md"
    static let areaList = "Areas/My Classrooms/To do.md"
    /// Another area's list: an action moved here is out of the notebook's lists.
    static let home = "Areas/Home/To do.md"

    var actions: [Action] = []
    var lists: [String] = [upperEl, roomSetup, areaList]
    private var revisions: [String: Int] = [:]
    /// Every call, in order.
    private(set) var calls: [(name: String, arguments: [String: JSONValue])] = []
    /// Thrown before any tool runs: Tide closed, a changed token.
    var failure: TideTransportError?
    /// Titles `add_action` refuses.
    var refusedTitles: Set<String> = []
    /// Someone else edits the list just before the next `add_action`.
    var editBeforeNextAdd = false
    /// Titles whose next write Tide answers "isn't in Tide's store yet".
    var notReadyOnce: Set<String> = []
    /// The headings each list has, when a test cares; a write naming another
    /// is refused, as Tide refuses it.
    var headings: [String: Set<String>] = [:]
    /// Holds calls of this tool (every tool when nil) at `gate`, so a test
    /// can act while a run is in flight. A held call that comes back to a
    /// cancelled task throws, as URLSession does.
    var gate: TideTestGate?
    var holdTool: String?

    var callNames: [String] { calls.map(\.name) }

    func callTool(_ name: String, arguments: [String: JSONValue]) async throws -> TideToolReply {
        calls.append((name, arguments))
        if let gate, holdTool == nil || holdTool == name {
            await gate.wait()
            if Task.isCancelled { throw CancellationError() }
        }
        if let failure { throw failure }
        switch name {
        case "get_area": return getArea(arguments)
        case "add_action": return addAction(arguments)
        case "complete_action": return completeAction(arguments)
        case "update_action": return updateAction(arguments)
        case "list_actions": return listActions(arguments)
        default: return Self.plainError("Unknown tool: \(name)")
        }
    }

    // MARK: - Test helpers

    @discardableResult
    func add(_ text: String, in file: String = upperEl, heading: String? = "This week", note: String? = nil,
             due: String? = nil, repeats: Bool = false) -> TideActionLink {
        actions.append(Action(text: text, note: note, file: file, heading: heading, due: due, repeats: repeats))
        bump(file)
        return TideActionLink(file: file, text: text)
    }

    func action(_ text: String) -> Action? { actions.first { $0.text == text } }

    func action(notebookID id: UUID) -> Action? {
        actions.first { $0.note?.contains("notebook:\(id.uuidString)") == true }
    }

    func setState(_ state: String, of text: String) {
        guard let index = actions.firstIndex(where: { $0.text == text }) else { return }
        actions[index].state = state
        bump(actions[index].file)
    }

    func reword(_ text: String, to newText: String) {
        guard let index = actions.firstIndex(where: { $0.text == text }) else { return }
        actions[index].text = newText
        bump(actions[index].file)
    }

    func move(_ text: String, to file: String) {
        guard let index = actions.firstIndex(where: { $0.text == text }) else { return }
        bump(actions[index].file)
        actions[index].file = file
        bump(file)
    }

    func revision(of file: String) -> String { "rev-\(revisions[file] ?? 0)" }

    // MARK: - Tools

    private func getArea(_ arguments: [String: JSONValue]) -> TideToolReply {
        guard arguments["dir"]?.stringValue == Self.area else {
            return Self.refusal(rule: "no area is named that", fix: "name it as list_areas does")
        }
        let boxes = actions.indices.filter { index in
            lists.contains(actions[index].file) && ["open", "waiting", "someday"].contains(actions[index].state)
        }.map { row(at: $0) }
        let queueFiles: [[String: Any]] = lists.map { file in
            ["file": file, "feeds": true, "open": actions.filter { $0.file == file && $0.state == "open" }.count]
        }
        return Self.reply(["dir": Self.area, "name": Self.area, "boxes": boxes, "queue_files": queueFiles])
    }

    private func addAction(_ arguments: [String: JSONValue]) -> TideToolReply {
        guard let file = arguments["file"]?.stringValue, let text = arguments["action"]?.stringValue else {
            return Self.plainError("action is required")
        }
        if editBeforeNextAdd {
            editBeforeNextAdd = false
            bump(file)
        }
        if refusedTitles.contains(text) {
            return Self.refusal(rule: "due is already past", fix: "leave due off")
        }
        if let refusal = notReady(text) { return refusal }
        let heading = arguments["heading"]?.stringValue
        if let heading, let known = headings[file], !known.contains(heading) {
            let has = known.sorted().joined(separator: ", ")
            return Self.refusal(rule: "no heading \"\(heading)\" in \(file) — it has \(has)",
                                fix: "use one of those as list_actions returns it")
        }
        if actions.contains(where: { $0.file == file }) {
            guard let position = arguments["position"]?.intValue else {
                return Self.refusal(rule: "position is required — appending would say the newest thing matters least",
                                    fix: "read list_actions or get_project, choose where it goes (count + 1 is last)")
            }
            guard let revision = arguments["revision"]?.stringValue else {
                return Self.refusal(rule: "revision is required with a position",
                                    fix: "pass the revision list_actions or get_project returned for this list")
            }
            guard revision == self.revision(of: file) else {
                return Self.refusal(rule: "\(file) has changed since it was read",
                                    fix: "read list_actions or get_project again and choose the position on that")
            }
            let count = siblings(file: file, heading: heading).count
            guard (1...(count + 1)).contains(position) else {
                return Self.refusal(rule: "position \(position) is not in the list", fix: "choose 1 to \(count + 1)")
            }
        }
        actions.append(Action(text: text, note: arguments["note"]?.stringValue, file: file, heading: heading,
                              due: arguments["due"]?.stringValue, start: arguments["start"]?.stringValue))
        bump(file)
        return writeReply(at: actions.count - 1, outcome: nil)
    }

    private func completeAction(_ arguments: [String: JSONValue]) -> TideToolReply {
        let index: Int
        switch named(arguments) {
        case .success(let found): index = found
        case .failure(let refusal): return refusal.reply
        }
        if let refusal = notReady(actions[index].text) { return refusal }
        if actions[index].state == "dropped" {
            return Self.refusal(rule: "\"\(actions[index].text)\" was dropped",
                                fix: "a dropped action is closed; leave it")
        }
        bump(actions[index].file)
        if actions[index].repeats {
            actions[index].due = "2026-10-26"
            return writeReply(at: index, outcome: "rolled")
        }
        let wasClosed = actions[index].state == "done"
        actions[index].state = "done"
        return writeReply(at: index, outcome: wasClosed ? "already_closed" : "completed")
    }

    /// A note-only `update_action`.
    private func updateAction(_ arguments: [String: JSONValue]) -> TideToolReply {
        let index: Int
        switch named(arguments) {
        case .success(let found): index = found
        case .failure(let refusal): return refusal.reply
        }
        guard let note = arguments["note"]?.stringValue else {
            return Self.refusal(rule: "nothing to change", fix: "pass a field, text, or a position")
        }
        actions[index].note = note
        bump(actions[index].file)
        return writeReply(at: index, outcome: nil)
    }

    struct Refused: Error {
        let reply: TideToolReply
    }

    /// The action a call names by its words, among every row of the list,
    /// ticked ones included: more than one with them is refused, as Tide's
    /// `namedAction` refuses it.
    private func named(_ arguments: [String: JSONValue]) -> Result<Int, Refused> {
        guard let file = arguments["file"]?.stringValue, let text = arguments["action"]?.stringValue else {
            return .failure(Refused(reply: Self.plainError("action is required")))
        }
        let matches = actions.indices.filter { actions[$0].file == file && actions[$0].text == text }
        guard matches.count < 2 else {
            return .failure(Refused(reply: Self.refusal(rule: "\"\(text)\" matches more than one action in \(file)",
                                                        fix: "quote one action's exact text")))
        }
        guard let index = matches.first else {
            return .failure(Refused(reply: Self.refusal(rule: "no action reads \"\(text)\" in \(file)",
                                                        fix: "copy the text from list_actions")))
        }
        return .success(index)
    }

    private func notReady(_ text: String) -> TideToolReply? {
        guard notReadyOnce.remove(text) != nil else { return nil }
        return Self.refusal(rule: "\"\(text)\" isn't in Tide's store yet", fix: "try again in a moment")
    }

    private func listActions(_ arguments: [String: JSONValue]) -> TideToolReply {
        let file = arguments["file"]?.stringValue
        let state = arguments["state"]?.stringValue ?? "open"
        let rows = actions.indices
            .filter { (file == nil || actions[$0].file == file) && actions[$0].state == state }
            .map { row(at: $0, link: false) }
        let limit = arguments["limit"]?.intValue ?? 200
        var out: [Any] = Array(rows.prefix(limit))
        if rows.count > limit { out.append(["truncated": true, "shown": limit, "of": rows.count, "fix": "narrow"]) }
        return Self.reply(out)
    }

    // MARK: - Shapes

    private func siblings(file: String, heading: String?) -> [Int] {
        actions.indices.filter { actions[$0].file == file && actions[$0].heading == heading }
    }

    private func row(at index: Int, link: Bool = true) -> [String: Any] {
        let action = actions[index]
        let section = siblings(file: action.file, heading: action.heading)
        var row: [String: Any] = [
            "action": action.text, "file": action.file, "state": action.state,
            "position": (section.firstIndex(of: index) ?? 0) + 1, "of": section.count,
            "started": true, "available": true, "next": false, "on_phone": false, "feeds_next_actions": true,
            "revision": revision(of: action.file)
        ]
        if let heading = action.heading { row["heading"] = heading }
        if let note = action.note { row["note"] = note }
        if let due = action.due { row["due"] = due }
        if link { row["link"] = TideActionLink(file: action.file, text: action.text).string }
        return row
    }

    private func writeReply(at index: Int, outcome: String?) -> TideToolReply {
        var reply: [String: Any] = [
            "ok": true, "action": row(at: index), "revision": revision(of: actions[index].file),
            "phone": ["changed": false, "now_on": [String](), "no_longer_on": [String]()], "warnings": [String]()
        ]
        if let outcome { reply["outcome"] = outcome }
        return Self.reply(reply)
    }

    private func bump(_ file: String) {
        revisions[file, default: 0] += 1
    }

    private static func reply(_ object: Any) -> TideToolReply {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return TideToolReply(text: String(bytes: data, encoding: .utf8) ?? "", isError: false)
    }

    private static func refusal(rule: String, fix: String) -> TideToolReply {
        let body: [String: Any] = ["ok": false, "refused": [["rule": rule, "fix": fix]]]
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        return TideToolReply(text: String(bytes: data, encoding: .utf8) ?? "", isError: true)
    }

    private static func plainError(_ message: String) -> TideToolReply {
        let data = (try? JSONSerialization.data(withJSONObject: ["ok": false, "error": message])) ?? Data()
        return TideToolReply(text: String(bytes: data, encoding: .utf8) ?? "", isError: true)
    }
}

/// Holds a fake Tide's calls until a test opens it.
@MainActor
final class TideTestGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var isOpen = false
    /// How many calls have reached the gate.
    private(set) var arrivals = 0

    func wait() async {
        arrivals += 1
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let held = waiters
        waiters = []
        held.forEach { $0.resume() }
    }
}
