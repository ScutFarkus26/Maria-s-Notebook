// TideSyncEngine.swift
// One run of sharing to-dos between the notebook and Tide (plan "Simplify
// the app", Phase 10).

import Foundation
import OSLog

/// One run of the sharing: read Tide's lists, compare them with the
/// notebook's linked to-dos, and carry across what changed since the two
/// last agreed.
///
/// - **Read**: one `get_area` of My Classrooms, every unfinished action of
///   its lists. The plan said `changes_since` with a saved cursor; it isn't
///   used, because a call without an author or device filter moves the one
///   cursor Danny's Claude sessions rely on (`StoreTools+Changes.swift`), and
///   a snapshot also sees what a cursor can't (a list moved, a heading
///   renamed). An action is gone from the read when it was ticked, dropped,
///   deleted or moved out of the area's lists; all four close the
///   notebook's copy, judged only for the lists the sharing covers.
/// - **The notebook line**: every linked action carries `notebook:<uuid>` in
///   its Tide note: written by `add_action` for one sent from here, added by
///   `update_action` for one made in Tide or matched at the first run. A
///   to-do finds its action by that line first, anywhere in the area, so a
///   reword or a move in Tide keeps the link, and two actions with the same
///   words stay apart.
/// - **Ticks** go first, from what both apps last agreed
///   (`TideSyncState.agreedOpen`): a tick here goes to `complete_action`; an
///   action gone from Tide ticks the copy here. An untick on either side
///   isn't carried. A tick here outlives its to-do (`pendingTicks`), so
///   clearing it before the Mac has told Tide doesn't lose it; a repeat
///   Tide already rolled on (ticked there too) isn't ticked again.
/// - **Send**: every open notebook to-do with no Tide link, no linked work
///   (an automatic work check-in) and not someday, with its line and the
///   children's names in the note, and a later planned day as Tide's start.
/// - **Show**: every open action of the lists Danny picked that no notebook
///   to-do holds becomes one, unless its to-do was deleted here before the
///   action took the notebook line (`TideSyncState.unmarkedLinks`). A later
///   start in Tide plans it for that day here. It is saved, with what the
///   sync remembers, before any note is marked.
/// - **Wording**: once sent, Tide keeps the wording; a title edit here
///   doesn't travel. A to-do made in Tide takes a reword or a new due date
///   there, and a new title or due date here goes to Tide (`update_action`):
///   the due date measured from the one both last agreed
///   (`TideSyncState.agreedDue`), Tide's change winning. Its note is copied
///   once; one the first run matched keeps its own words.
///
/// Nothing is linked, sent or shown until Danny confirms the first run's
/// matches (`TideFirstRunProposal`). Every notebook change goes through
/// `TideTodoStore`.
final class TideSyncEngine {
    let tools: TideTools
    let store: TideTodoStore
    /// Changed only by the run; read by the service and tests.
    var state: TideSyncState
    let persist: (TideSyncState) -> Void
    let calendar: Calendar
    /// To-dos Tide refused, with the title it refused: not sent again until
    /// the title changes, so a refusal isn't repeated every few minutes.
    var refusedSends: [UUID: String] = [:]
    /// Actions whose note Tide wouldn't take the notebook line in (two with
    /// the same words, say), with their list's revision then: asked again
    /// once the list has changed.
    var unmarkable: [String: String] = [:]
    /// Edits made here to to-dos made in Tide that Tide wouldn't take, or a
    /// due date already past: not tried, or said, again until they change
    /// here (`isHeld`).
    var heldEdits: Set<String> = []
    /// The last area read, for Settings' pickers: one read per run.
    private(set) var lastArea: TideArea?

    static let logger = Logger(subsystem: "CosmicDaybook", category: "TideSync")

    init(
        transport: TideTransport,
        store: TideTodoStore,
        state: TideSyncState,
        calendar: Calendar = AppCalendar.shared,
        persist: @escaping (TideSyncState) -> Void
    ) {
        tools = TideTools(transport: transport)
        self.store = store
        self.state = state
        self.calendar = calendar
        self.persist = persist
    }

    /// One run. Before the first run is confirmed it only reads and proposes.
    func run(_ settings: TideSyncSettings, now: Date = Date()) async -> TideSyncResult {
        await perform(settings, confirming: nil, now: now)
    }

    /// Links the matches Danny kept, then runs: from here on, to-dos go across.
    func confirmFirstRun(
        _ matches: [TideFirstRunProposal.Match], settings: TideSyncSettings, now: Date = Date()
    ) async -> TideSyncResult {
        await perform(settings, confirming: matches, now: now)
    }

    // MARK: - The run

    private func perform(
        _ settings: TideSyncSettings, confirming matches: [TideFirstRunProposal.Match]?, now: Date
    ) async -> TideSyncResult {
        let area: TideArea
        do {
            area = try await tools.area(TideSyncSettings.area)
        } catch {
            // A tick made here is remembered even while Tide can't be
            // reached, so clearing the to-do before it answers doesn't lose it.
            if notePendingTicks(in: store.todos(alsoClosed: state.openIDs)) { persist(state) }
            return .stopped(TideSyncProblem(readingArea: error))
        }
        lastArea = area
        var run = Run(area: area, settings: settings, todos: store.todos(alsoClosed: state.openIDs))

        if state.firstRunConfirmedAt == nil {
            if let matches {
                linkFirstRun(matches, in: &run)
                state.firstRunConfirmedAt = now
                persist(state)
            } else if run.todos.contains(where: { $0.tideLink != nil }) {
                // Linked already (another Mac, or this one before its settings
                // were cleared): there is nothing left to match.
                state.firstRunConfirmedAt = now
            } else {
                return .needsFirstRunOK(proposal(for: run))
            }
        }

        do {
            notePendingTicks(in: run.todos)
            adoptSentActions(in: &run)
            try await judgeLinkedTodos(in: &run, now: now)
            try await carryTicks(in: &run)
            try await carryEdits(in: &run)
            try await send(in: &run, now: now)
            showTideActions(in: &run, now: now)
            // Saved before any note is marked: a note naming a to-do that
            // never reached the store keeps its action out for good.
            persist(state)
            guard store.save() else { return .stopped(.saveFailed) }
            try await markLinkedActions(in: &run)
        } catch {
            _ = store.save()
            persist(state)
            return .stopped(TideSyncProblem(error))
        }

        state.keep(only: Set(run.todos.map(\.id)))
        // An action reworded this run is known by its new address.
        let addresses = (run.actions + Array(run.actionFor.values)).compactMap { $0.actionLink?.string }
        state.keepUnmarkedLinks(at: Set(addresses))
        state.lastSyncAt = now
        persist(state)
        guard store.save() else { return .stopped(.saveFailed) }
        let report = run.report
        Self.logger.info("Tide sync: sent \(report.sent), showed \(report.pulled)")
        Self.logger.info("Tide sync: closed \(report.closedHere) here, ticked \(report.tickedInTide) in Tide")
        return .synced(run.report)
    }

    /// An edit made here to a to-do made in Tide: its words, its due date
    /// ("" clears it), or both; nil leaves that one as Tide has it.
    struct Edit {
        let id: UUID
        let title: String
        let action: TideAction
        let text: String?
        let due: String?
    }

    /// What one run is working from.
    struct Run {
        let settings: TideSyncSettings
        let area: TideArea
        /// The lists whose actions show in the notebook.
        let shown: Set<String>
        /// The lists whose read can say an action is gone: the shown ones and
        /// the one new to-dos go to.
        let judged: Set<String>
        let destinationIsThere: Bool
        /// Top-level actions of every list Tide sent (the area's lists that
        /// feed Next Actions, picked or not).
        let actions: [TideAction]
        /// Actions by address; more than one when a list has the same words twice.
        let byLink: [String: [TideAction]]
        /// Actions by the notebook to-do their note names.
        let byNotebookID: [UUID: TideAction]
        var todos: [TideNotebookTodo]
        /// Actions a notebook to-do holds now, by `TideAction.key`.
        var claimed = Set<String>()
        /// Each linked to-do's action in this read.
        var actionFor: [UUID: TideAction] = [:]
        /// Linked to-dos ticked here while open in Tide.
        var ticks: [(id: UUID, action: TideAction)] = []
        /// Linked to-dos ticked here whose repeat Tide already rolled on,
        /// with its new due date: ticked there too.
        var rolledThere: [(id: UUID, due: String?)] = []
        /// Edits made here to to-dos made in Tide, to go across.
        var edits: [Edit] = []
        /// Each list's revision after this run's own writes to it.
        var revisions: [String: String] = [:]
        var report = TideSyncReport()

        init(area: TideArea, settings: TideSyncSettings, todos: [TideNotebookTodo]) {
            self.settings = settings
            self.area = area
            let feeding = Set(area.feedingLists.map(\.file))
            shown = feeding.filter(settings.shows)
            destinationIsThere = feeding.contains(settings.destinationFile)
            judged = destinationIsThere ? shown.union([settings.destinationFile]) : shown
            actions = (area.boxes ?? []).filter { action in
                action.partOf == nil && action.file.map(feeding.contains) == true
            }
            var byLink: [String: [TideAction]] = [:]
            var byNotebookID: [UUID: TideAction] = [:]
            for action in actions {
                if let link = action.actionLink?.string { byLink[link, default: []].append(action) }
                if let id = action.notebookID, byNotebookID[id] == nil { byNotebookID[id] = action }
            }
            self.byLink = byLink
            self.byNotebookID = byNotebookID
            self.todos = todos
            report.destinationGone = !destinationIsThere
        }

        /// The to-do at `index` holds `action` now.
        mutating func hold(_ action: TideAction, at index: Int) {
            claimed.insert(action.key)
            actionFor[todos[index].id] = action
        }

        mutating func setLink(_ link: String, title: String?, at index: Int) {
            todos[index].tideLink = link
            if let title, !title.isEmpty { todos[index].title = title }
        }
    }

    // MARK: - First run

    private func proposal(for run: Run) -> TideFirstRunProposal {
        let candidates = run.todos.filter(Self.isMatchable)
        let unfinished = run.actions.filter { $0.isUnfinished && $0.file.map(run.judged.contains) == true }
        let pairs = TideWordMatch.pairs(notebook: candidates, tide: unfinished)
        let byID = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let byLink = Dictionary(unfinished.compactMap { action in action.actionLink.map { ($0.string, action) } },
                                uniquingKeysWith: { first, _ in first })
        let matches = pairs.compactMap { pair -> TideFirstRunProposal.Match? in
            guard let todo = byID[pair.notebookID], let action = byLink[pair.tideLink],
                  let file = action.file else { return nil }
            return TideFirstRunProposal.Match(
                notebookID: pair.notebookID, notebookTitle: todo.title,
                tideLink: pair.tideLink, tideText: action.action,
                listName: TideActionLink.listName(ofFile: file), score: pair.score,
                isCheckIn: todo.hasLinkedWork
            )
        }
        let matchedTodos = Set(matches.map(\.notebookID))
        let matchedLinks = Set(matches.map(\.tideLink))
        let toShow = run.actions.filter { action in
            guard action.isOpen, let file = action.file, let link = action.actionLink?.string else { return false }
            return run.shown.contains(file) && !matchedLinks.contains(link) && action.notebookID == nil
        }
        let toSend = candidates.filter { Self.isSendable($0) && !matchedTodos.contains($0.id) }
        return TideFirstRunProposal(
            matches: matches,
            toSend: run.destinationIsThere ? toSend.count : 0,
            toShow: toShow.count,
            destinationName: TideActionLink.listName(ofFile: run.settings.destinationFile)
        )
    }

    /// Links the matches Danny kept that still hold: the to-do is still open
    /// and unlinked, and the action is still in Tide's lists. A work check-in
    /// can be matched: it is linked, never sent.
    private func linkFirstRun(_ matches: [TideFirstRunProposal.Match], in run: inout Run) {
        var linked: [String] = []
        for match in matches {
            guard let index = run.todos.firstIndex(where: { $0.id == match.notebookID }),
                  Self.isMatchable(run.todos[index]),
                  let action = run.byLink[match.tideLink]?.first(where: { !run.claimed.contains($0.key) })
            else { continue }
            store.link(match.notebookID, to: match.tideLink, title: nil)
            run.setLink(match.tideLink, title: nil, at: index)
            run.hold(action, at: index)
            state[todo: match.notebookID] = true
            linked.append(match.notebookID.uuidString)
        }
        state.firstRunLinked = linked
        _ = store.save()
    }
}
