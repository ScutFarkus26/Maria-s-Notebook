// TideSyncEngine+Steps.swift
// The steps of one run, in the order `perform` takes them.

import Foundation
import OSLog

extension TideSyncEngine {

    /// A Tide action carrying an unlinked to-do's `notebook:` line is that
    /// to-do: it was sent, and the notebook stopped before saving its link.
    func adoptSentActions(in run: inout Run) {
        for index in run.todos.indices where run.todos[index].tideLink == nil {
            let id = run.todos[index].id
            guard let action = run.byNotebookID[id], !run.claimed.contains(action.key),
                  let link = action.actionLink?.string else { continue }
            store.link(id, to: link, title: action.action)
            run.setLink(link, title: action.action, at: index)
            run.hold(action, at: index)
            // It was open when it was sent.
            state[todo: id] = true
            run.report.relinked += 1
        }
    }

    /// Each linked to-do against its action, then a tick on either side since
    /// the two last agreed.
    func judgeLinkedTodos(in run: inout Run) {
        for index in run.todos.indices {
            guard let stored = run.todos[index].tideLink.flatMap(TideActionLink.init) else { continue }
            let action = currentAction(for: stored, at: index, in: &run)
            // Gone from a list the sharing doesn't cover (unpicked, or no
            // longer in Tide) says nothing: leave the to-do be.
            if action == nil, !run.judged.contains(stored.file) { continue }
            judge(index, against: action, in: &run)
        }
    }

    /// The action a linked to-do is a copy of now: the one whose note names
    /// it, anywhere in the area's lists, or else one at its address that names
    /// no other to-do. One reworded or moved in Tide takes the to-do's new
    /// address and words with it.
    private func currentAction(for stored: TideActionLink, at index: Int, in run: inout Run) -> TideAction? {
        let id = run.todos[index].id
        // Linked earlier in this run (a first-run match, a send taken back).
        if let held = run.actionFor[id] { return held }
        if let named = run.byNotebookID[id], !run.claimed.contains(named.key) {
            if let link = named.actionLink?.string, link != stored.string {
                store.link(id, to: link, title: named.action)
                run.setLink(link, title: named.action, at: index)
                run.report.relinked += 1
            }
            run.hold(named, at: index)
            return named
        }
        let candidates = run.byLink[stored.string] ?? []
        guard let action = candidates.first(where: { candidate in
            !run.claimed.contains(candidate.key) && (candidate.notebookID == nil || candidate.notebookID == id)
        }) else { return nil }
        run.hold(action, at: index)
        return action
    }

    /// A tick on either side since the two last agreed. A to-do the sync
    /// knows nothing about (no agreed state) is never ticked on either side.
    private func judge(_ index: Int, against action: TideAction?, in run: inout Run) {
        let todo = run.todos[index]
        let agreedOpen = state[todo: todo.id]
        switch (todo.isCompleted, action) {
        case (false, let action?):
            state[todo: todo.id] = true
            if state.fromTide.contains(todo.id.uuidString) { followTide(todo, action) }
        case (true, let action?):
            // A tick here goes across only from open; from closed, Tide
            // reopened it, and an untick isn't carried.
            if agreedOpen { run.ticks.append((todo.id, action)) }
        case (false, nil):
            // Ticked, dropped, deleted or moved out in Tide. After both were
            // closed, an untick here isn't carried back.
            if agreedOpen {
                store.complete(todo.id)
                run.todos[index].isCompleted = true
                run.report.closedHere += 1
            }
            state[todo: todo.id] = false
        case (true, nil):
            state[todo: todo.id] = false
        }
    }

    /// A to-do made in Tide keeps Tide's words and due date. Its note was
    /// copied when it came in; a note added here stays.
    private func followTide(_ todo: TideNotebookTodo, _ action: TideAction) {
        let due = TideDay.date(action.due, calendar: calendar)
        guard todo.title != action.action || !TideDay.sameDay(todo.dueDate, due, calendar) else { return }
        store.update(todo.id, title: action.action, due: due)
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
        for tick in run.ticks {
            guard let file = tick.action.file else { continue }
            do {
                let reply = try await tools.completeAction(file: file, action: tick.action.action)
                run.revisions[file] = reply.revision
                if reply.outcome == "rolled" || reply.outcome == "routine_rolled" {
                    // A repeat in Tide moved on rather than finishing: so does the copy.
                    store.reopen(tick.id, due: TideDay.date(reply.action?.due, calendar: calendar))
                    state[todo: tick.id] = true
                    reopened = true
                } else {
                    state[todo: tick.id] = false
                }
                run.report.tickedInTide += 1
            } catch let error as TideToolError where error.isAmbiguous || error.isTemporary {
                // Tide can't tell which action the words name (the list has
                // more than one with them), or isn't ready: asked again next
                // run, and said plainly until Danny ticks it off in Tide.
                if error.isAmbiguous { run.report.notTicked.append(tick.action.action) }
                run.report.details.append("\(tick.action.action): \(error.details)")
            } catch let error as TideToolError {
                // Tide won't tick it (dropped there already): it stays ticked here.
                state[todo: tick.id] = false
                run.report.details.append("\(tick.action.action): \(error.details)")
            }
        }
    }

    /// Sends every sendable to-do, oldest first, each placed last under the
    /// chosen heading.
    func send(in run: inout Run, now: Date) async throws {
        guard run.destinationIsThere else { return }
        var place = try await placement(in: run)
        sending: for index in run.todos.indices where Self.isSendable(run.todos[index]) {
            let todo = run.todos[index]
            let title = todo.title.trimmed()
            guard !title.isEmpty, refusedSends[todo.id] != title else { continue }
            let new = TideTools.NewAction(
                file: run.settings.destinationFile, heading: place.heading, action: title,
                note: note(for: todo), position: place.position, revision: place.revision,
                due: dueArgument(todo.dueDate, now: now), start: startArgument(todo.scheduledDate, now: now)
            )
            do {
                let reply = try await tools.addAction(new)
                let link = reply.action?.actionLink?.string
                    ?? TideActionLink(file: run.settings.destinationFile, text: title).string
                store.link(todo.id, to: link, title: reply.action?.action)
                run.setLink(link, title: reply.action?.action, at: index)
                state[todo: todo.id] = true
                run.report.sent += 1
                // Saved at once, so stopping now can't send it twice.
                _ = store.save()
                persist(state)
                guard let added = reply.action else { break sending }
                place.position = added.of + 1
                place.revision = reply.revision
            } catch let error as TideToolError where error.isStaleRevision || error.isTemporary {
                // The list changed under the read, or Tide isn't ready: read
                // again next run, never send the same write again.
                run.report.tryAgain = true
                break sending
            } catch let error as TideToolError where error.isMissingHeading {
                run.report.headingGone = place.heading
                break sending
            } catch let error as TideToolError {
                refusedSends[todo.id] = title
                run.report.notSent.append(title)
                run.report.details.append("\(title): \(error.details)")
            }
        }
    }

    /// Where the next new action goes: last under the heading.
    private struct Placement {
        var heading: String?
        var position: Int?
        var revision: String?
    }

    /// The saved heading isn't checked against this read, which sees only the
    /// headings that hold an unfinished action: Tide refuses a missing one by
    /// name, and that refusal is what the status reports.
    private func placement(in run: Run) async throws -> Placement {
        let file = run.settings.destinationFile
        let heading = run.settings.destinationHeading ?? run.area.headings(of: file).first
        let rows = run.actions.filter { $0.file == file }
        let section = rows.filter { row in
            guard let heading else { return row.heading == nil }
            return row.heading?.caseInsensitiveCompare(heading) == .orderedSame
        }
        // A tick this run changed the list's revision, not its counts.
        let revision = run.revisions[file]
        if let row = section.first {
            return Placement(heading: heading, position: row.of + 1, revision: revision ?? row.revision)
        }
        if let row = rows.first { return Placement(heading: heading, position: 1, revision: revision ?? row.revision) }
        // Nothing unfinished in the list: a closed action, if it holds one,
        // still carries the revision a positioned write needs.
        for state in ["done", "dropped"] {
            if let row = try await tools.actions(inFile: file, state: state, limit: 1).first {
                return Placement(heading: heading, position: 1, revision: row.revision)
            }
        }
        return Placement(heading: heading, position: nil, revision: nil)
    }

    /// Every open action of the picked lists that no notebook to-do holds
    /// becomes one. One that came from the notebook never comes back as a
    /// second copy, even when its to-do is gone: by its notebook line, or,
    /// for one whose note couldn't take the line, by its address, once for
    /// each to-do deleted here (`TideSyncState.unmarkedLinks`).
    func showTideActions(in run: inout Run) {
        let present = Set(run.todos.map(\.id.uuidString))
        var deletedHere: [String: Int] = [:]
        for (id, link) in state.unmarkedLinks where !present.contains(id) {
            deletedHere[link, default: 0] += 1
        }
        for action in run.actions where action.isOpen && action.notebookID == nil {
            guard let file = action.file, run.shown.contains(file), !run.claimed.contains(action.key),
                  let link = action.actionLink?.string else { continue }
            if let count = deletedHere[link], count > 0 {
                deletedHere[link] = count - 1
                continue
            }
            let notes = TideNotebookMarker.removing(from: action.note)
            let due = TideDay.date(action.due, calendar: calendar)
            let id = store.add(title: action.action, notes: notes, due: due, link: link)
            run.todos.append(TideNotebookTodo(
                id: id, title: action.action, notes: notes, isCompleted: false, hasLinkedWork: false,
                isSomeday: false, tideLink: link, studentIDs: [], dueDate: due, scheduledDate: nil, createdAt: nil
            ))
            run.hold(action, at: run.todos.count - 1)
            state[todo: id] = true
            state.fromTide.insert(id.uuidString)
            run.report.pulled += 1
        }
    }

    /// Writes the `notebook:` line into the note of each linked action that
    /// lacks one (made in Tide, or matched at the first run), after Danny's
    /// own words, so a reword or a move in Tide keeps the link.
    ///
    /// Until the line is written, the action is known by its address alone,
    /// which is kept (`TideSyncState.unmarkedLinks`) so the action doesn't
    /// come back as a new to-do if this one is deleted.
    func markLinkedActions(in run: inout Run) async throws {
        for todo in run.todos where !todo.isCompleted && todo.tideLink != nil {
            guard let action = run.actionFor[todo.id], let file = action.file else { continue }
            guard action.notebookID == nil else {
                state.unmarkedLinks[todo.id.uuidString] = nil
                continue
            }
            state.unmarkedLinks[todo.id.uuidString] = action.actionLink?.string
            guard !unmarkable.contains(action.key) else { continue }
            let existing = (action.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let marker = TideNotebookMarker.line(for: todo.id)
            do {
                _ = try await tools.updateNote(
                    file: file, action: action.action, note: existing.isEmpty ? marker : existing + "\n\n" + marker
                )
                state.unmarkedLinks[todo.id.uuidString] = nil
                run.report.marked += 1
            } catch let error as TideToolError where error.isTemporary {
                continue
            } catch let error as TideToolError {
                // Two actions with these words, or Danny's note changed under
                // the read: the link still holds by address.
                unmarkable.insert(action.key)
                Self.logger.notice("Tide note not marked: \(error.details, privacy: .private)")
            }
        }
    }

    // MARK: - Helpers

    /// Open, unlinked, not an automatic work check-in, and not someday.
    static func isSendable(_ todo: TideNotebookTodo) -> Bool {
        isMatchable(todo) && !todo.hasLinkedWork && !todo.isSomeday
    }

    /// What the first run may link: any open, unlinked to-do, work check-ins
    /// included (they are linked, never sent).
    static func isMatchable(_ todo: TideNotebookTodo) -> Bool {
        !todo.isCompleted && todo.tideLink == nil
    }

    /// The Tide note for a to-do: the children it is about, then its line.
    private func note(for todo: TideNotebookTodo) -> String {
        let names = store.studentNames(for: todo.studentIDs)
        let marker = TideNotebookMarker.line(for: todo.id)
        guard let last = names.last else { return marker }
        let joined = names.count == 1 ? last : names.dropLast().joined(separator: ", ") + " and " + last
        return "For \(joined).\n\n\(marker)"
    }

    /// The due date to send: only today or later, since Tide refuses one
    /// already past (the notebook keeps its own).
    private func dueArgument(_ due: Date?, now: Date) -> String? {
        guard let due, calendar.startOfDay(for: due) >= calendar.startOfDay(for: now) else { return nil }
        return TideDay.string(due, calendar: calendar)
    }

    /// A day the to-do is planned for after today becomes Tide's start: it
    /// waits out of Next Actions until then, as it waits in Upcoming here.
    private func startArgument(_ scheduled: Date?, now: Date) -> String? {
        guard let scheduled, calendar.startOfDay(for: scheduled) > calendar.startOfDay(for: now) else { return nil }
        return TideDay.string(scheduled, calendar: calendar)
    }
}
