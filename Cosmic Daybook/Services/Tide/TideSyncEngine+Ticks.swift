// TideSyncEngine+Ticks.swift
// Ticks made here going to Tide: the linked to-dos ticked since the two
// apps last agreed, those cleared or deleted before the Mac told Tide, and
// repeats Tide already rolled on.

import Foundation

extension TideSyncEngine {

    /// Remembers each linked to-do ticked here while both apps last agreed
    /// it was open, so its tick outlives it: cleared or deleted before the
    /// Mac has told Tide, it still goes across (bug hunt 2026-11-02 #11). One
    /// unticked again is forgotten. Returns whether anything changed.
    @discardableResult
    func notePendingTicks(in todos: [TideNotebookTodo]) -> Bool {
        var changed = false
        for todo in todos {
            guard let link = todo.tideLink else { continue }
            let pending = todo.isCompleted && state[todo: todo.id] ? link : nil
            guard state.pendingTicks[todo.id.uuidString] != pending else { continue }
            state.pendingTicks[todo.id.uuidString] = pending
            changed = true
        }
        return changed
    }

    /// To-dos deleted here, ticked, with their links, read as they went
    /// (`TideSyncService`): one whose tick hasn't gone across is kept, so the
    /// next run still ticks its action.
    func rememberDeletedTicks(_ ticks: [(id: UUID, link: String)]) {
        var changed = false
        for tick in ticks where state[todo: tick.id] && state.pendingTicks[tick.id.uuidString] != tick.link {
            state.pendingTicks[tick.id.uuidString] = tick.link
            changed = true
        }
        if changed { persist(state) }
    }

    /// A repeat whose due date Tide moved past the one both apps last agreed:
    /// ticked in Tide too, which rolled it on (#46).
    func hasRolledOn(_ action: TideAction, since agreed: String?) -> Bool {
        guard action.repeats, let agreed, !agreed.isEmpty, let due = action.due else { return false }
        return due > agreed
    }

    /// Ticks made here, before the sends: a repeat that rolls in Tide reopens
    /// its copy here, which must not take a just-sent next occurrence with it.
    func carryTicks(in run: inout Run) async throws {
        var reopened = false
        defer {
            // A reopened copy may have taken its unsent next occurrence with
            // it (`TodoCompletionService.reopen`): send from the notebook as it is.
            if reopened { run.todos = store.todos(alsoClosed: state.openIDs) }
        }
        for rolled in run.rolledThere {
            store.reopen(rolled.id, due: TideDay.date(rolled.due, calendar: calendar))
            state.agreedDue[rolled.id.uuidString] = rolled.due ?? ""
            state.pendingTicks[rolled.id.uuidString] = nil
            reopened = true
        }
        for tick in run.ticks {
            guard let file = tick.action.file else { continue }
            do {
                let reply = try await tools.completeAction(file: file, action: tick.action.action)
                run.revisions[file] = reply.revision
                if reply.outcome == "rolled" || reply.outcome == "routine_rolled" {
                    // A repeat in Tide moved on rather than finishing: so does the copy.
                    store.reopen(tick.id, due: TideDay.date(reply.action?.due, calendar: calendar))
                    state[todo: tick.id] = true
                    state.agreedDue[tick.id.uuidString] = reply.action?.due ?? ""
                    reopened = true
                } else {
                    state[todo: tick.id] = false
                }
                state.pendingTicks[tick.id.uuidString] = nil
                run.report.tickedInTide += 1
            } catch let error as TideToolError where error.isAmbiguous || error.isTemporary {
                // Tide can't tell which action the words name (the list has
                // more than one with them), or isn't ready: asked again next
                // run, and said plainly until Danny ticks it off in Tide.
                notTickedYet(tick.action.action, error, in: &run)
            } catch let error as TideToolError {
                // Tide won't tick it (dropped there already): it stays ticked here.
                state[todo: tick.id] = false
                state.pendingTicks[tick.id.uuidString] = nil
                run.report.details.append("\(tick.action.action): \(error.details)")
            }
        }
        try await carryTicksOfGoneTodos(in: &run)
    }

    /// Ticks made here on to-dos gone from the notebook since, each action
    /// found as a linked to-do finds its own: by its notebook line, else at
    /// its address. One closed or gone in Tide already needs nothing.
    private func carryTicksOfGoneTodos(in run: inout Run) async throws {
        let present = Set(run.todos.map(\.id.uuidString))
        for (key, address) in state.pendingTicks.sorted(by: { $0.key < $1.key }) where !present.contains(key) {
            guard let id = UUID(uuidString: key), let link = TideActionLink(address) else {
                state.pendingTicks[key] = nil
                continue
            }
            let named = run.byNotebookID[id].flatMap { run.claimed.contains($0.key) ? nil : $0 }
            let found = named ?? run.byLink[address]?.first { candidate in
                !run.claimed.contains(candidate.key) && (candidate.notebookID == nil || candidate.notebookID == id)
            }
            guard let action = found, let file = action.file else {
                // Gone from a list the sharing doesn't cover says nothing:
                // kept until it does.
                if run.judged.contains(link.file) { state.pendingTicks[key] = nil }
                continue
            }
            run.claimed.insert(action.key)
            guard !hasRolledOn(action, since: state.agreedDue[key]) else {
                state.pendingTicks[key] = nil
                continue
            }
            do {
                let reply = try await tools.completeAction(file: file, action: action.action)
                run.revisions[file] = reply.revision
                state.pendingTicks[key] = nil
                run.report.tickedInTide += 1
            } catch let error as TideToolError where error.isAmbiguous || error.isTemporary {
                notTickedYet(action.action, error, in: &run)
            } catch let error as TideToolError {
                state.pendingTicks[key] = nil
                run.report.details.append("\(action.action): \(error.details)")
            }
        }
    }

    /// A tick asked again next run: said plainly when Tide can't aim it,
    /// sooner when Tide isn't ready.
    private func notTickedYet(_ words: String, _ error: TideToolError, in run: inout Run) {
        if error.isAmbiguous {
            run.report.notTicked.append(words)
        } else {
            run.report.tryAgain = true
        }
        run.report.details.append("\(words): \(error.details)")
    }
}
