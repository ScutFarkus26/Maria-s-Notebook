// WorkLogStatusMenu.swift
// The status half of every work right-click menu.
//
// One builder for the Scheduled strip's pills, the work grid's cards, the
// selection bar and Today's rows, so the five statuses read the same
// everywhere and a menu can never offer a word the log sheet does not. With
// several children on the target — a grouped pill, or a linked-copies row —
// it offers "Everyone" and then one submenu per child, which is how a guide
// logs "all three mastered it, but Naomi needs another go" without opening
// anything.

import CoreData
import SwiftUI

struct WorkLogStatusMenu: View {

    /// One child's row, named for her submenu.
    struct Child: Identifiable {
        let id: UUID
        let name: String
        let work: CDWorkModel
    }

    /// The rows "Everyone" acts on.
    let targets: [CDWorkModel]
    /// One submenu each, shown only when there is more than one.
    var children: [Child] = []
    let onLog: ([CDWorkModel], WorkStatus) -> Void

    var body: some View {
        if children.count > 1 {
            Menu {
                statusButtons(for: targets)
            } label: {
                Label("Everyone", systemImage: "person.3")
            }
            ForEach(children) { child in
                Menu {
                    statusButtons(for: [child.work])
                } label: {
                    Label(child.name, systemImage: "person")
                }
            }
        } else {
            Menu {
                statusButtons(for: targets)
            } label: {
                Label(label, systemImage: "checkmark.circle")
            }
        }
    }

    private var label: String {
        targets.count > 1 ? "Log \(targets.count) as" : "Log as"
    }

    /// Working and Needs Review above the line, the three closing verdicts
    /// below it. A checkmark only when every target already has the status;
    /// a mixed selection shows none rather than claiming one of them.
    @ViewBuilder
    private func statusButtons(for rows: [CDWorkModel]) -> some View {
        ForEach(WorkStatus.pickable) { status in
            if status == WorkStatus.closedCases.first {
                Divider()
            }
            let isCurrent = !rows.isEmpty && rows.allSatisfy { $0.status == status }
            Button {
                onLog(rows, status)
            } label: {
                Label(status.displayName, systemImage: isCurrent ? "checkmark" : status.iconName)
            }
        }
    }

    // MARK: - Resolving children

    /// The children on a linked-copies group, one per row, named the way the
    /// rest of the app names them. A shared row or a single row yields one
    /// child, so the per-child submenus stay hidden.
    static func children(
        of group: WorkGroup, in context: NSManagedObjectContext
    ) -> [Child] {
        guard case .linkedCopies = group.shape else {
            return group.anchor.id.map { [Child(id: $0, name: "", work: group.anchor)] } ?? []
        }
        return group.members.compactMap { row in
            guard let id = row.id, let owner = WorkGrouping.owner(of: row) else { return nil }
            let name = context.object(CDStudent.self, id: owner).map(\.shortName) ?? "Student"
            return Child(id: id, name: name, work: row)
        }
    }
}
