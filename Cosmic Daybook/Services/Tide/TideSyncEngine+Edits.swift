// TideSyncEngine+Edits.swift
// A to-do made in Tide, edited on either side: a reword or a new due date in
// Tide comes here, and a new title or due date here goes to Tide (bug hunt
// 2026-11-02 #3; before, every edit here was undone on the next run).

import Foundation

extension TideSyncEngine {

    /// A to-do made in Tide, open on both sides. A reword in Tide came here
    /// already, with its new address (`currentAction`), so different words
    /// now are an edit here, which goes to Tide. The due date is measured
    /// from the one both last agreed (`TideSyncState.agreedDue`): a change in
    /// Tide comes here, winning over one made here since; one made only here
    /// goes to Tide. With nothing agreed yet (sharing from before this), Tide's
    /// comes here, as it always did.
    func compareWithTide(_ index: Int, _ action: TideAction, now: Date, in run: inout Run) {
        let todo = run.todos[index]
        let key = todo.id.uuidString
        let tideDue = action.due ?? ""
        let hereDue = todo.dueDate.map { TideDay.string($0, calendar: calendar) } ?? ""
        var due: String?
        if state.agreedDue[key] != tideDue {
            if hereDue != tideDue {
                let date = TideDay.date(action.due, calendar: calendar)
                store.update(todo.id, title: todo.title, due: date)
                run.todos[index].dueDate = date
            }
            state.agreedDue[key] = tideDue
        } else if hereDue != tideDue {
            due = dueToCarry(hereDue, of: todo, now: now, in: &run)
        }
        let words = todo.title.trimmed()
        let reworded = !words.isEmpty && words != action.action && !isHeld(todo.id, "title", words)
        guard reworded || due != nil else { return }
        run.edits.append(Edit(id: todo.id, title: todo.title, action: action, text: reworded ? words : nil, due: due))
    }

    /// The due date to send for one set or cleared here, or nil when it can't
    /// go: Tide takes only today or later, so an earlier day stays here and
    /// is said once, never asked of Tide every run.
    private func dueToCarry(_ hereDue: String, of todo: TideNotebookTodo, now: Date, in run: inout Run) -> String? {
        guard !isHeld(todo.id, "due", hereDue) else { return nil }
        if let date = todo.dueDate, calendar.startOfDay(for: date) < calendar.startOfDay(for: now) {
            hold(todo.id, "due", hereDue)
            run.report.pastDue.append(todo.title)
            return nil
        }
        return hereDue
    }

    /// The edits made here, after the ticks: one `update_action` each, words
    /// and date together. New words give the action a new address, saved at
    /// once, as a send is.
    func carryEdits(in run: inout Run) async throws {
        for edit in run.edits {
            guard let file = edit.action.file, let index = run.todos.firstIndex(where: { $0.id == edit.id }) else {
                continue
            }
            let key = edit.id.uuidString
            do {
                let reply = try await tools.updateAction(
                    file: file, action: edit.action.action, text: edit.text, due: edit.due
                )
                run.revisions[file] = reply.revision
                if let due = edit.due { state.agreedDue[key] = due }
                if let changed = reply.action {
                    // Marking names it by its words now.
                    run.actionFor[edit.id] = changed
                    run.claimed.insert(changed.key)
                }
                if let text = edit.text {
                    let link = reply.action?.actionLink?.string ?? TideActionLink(file: file, text: text).string
                    store.link(edit.id, to: link, title: reply.action?.action)
                    run.setLink(link, title: reply.action?.action, at: index)
                    if state.unmarkedLinks[key] != nil { state.unmarkedLinks[key] = link }
                    _ = store.save()
                    persist(state)
                }
                run.report.edited += 1
            } catch let error as TideToolError where error.isTemporary {
                run.report.tryAgain = true
            } catch let error as TideToolError {
                // It stays changed here only, and isn't tried again until it
                // changes here once more.
                if let text = edit.text { hold(edit.id, "title", text) }
                if let due = edit.due { hold(edit.id, "due", due) }
                run.report.notCarried.append(edit.title)
                run.report.details.append("\(edit.title): \(error.details)")
            }
        }
    }

    /// Whether this edit to this to-do was refused, or said, already.
    private func isHeld(_ id: UUID, _ field: String, _ value: String) -> Bool {
        heldEdits.contains(Self.heldKey(id, field, value))
    }

    private func hold(_ id: UUID, _ field: String, _ value: String) {
        heldEdits.insert(Self.heldKey(id, field, value))
    }

    private static func heldKey(_ id: UUID, _ field: String, _ value: String) -> String {
        "\(id.uuidString)\u{1F}\(field)\u{1F}\(value)"
    }
}
