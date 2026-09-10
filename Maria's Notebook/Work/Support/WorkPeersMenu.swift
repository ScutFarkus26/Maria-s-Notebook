// WorkPeersMenu.swift
// "Who else has this?" as a context-menu item.
//
// Two shapes of the same question. From a work card it means the same work —
// same lesson, same title, however the children came by it. From a lesson it
// means work on that lesson, whatever the work is.
//
// The managed object context is handed in rather than read from
// `@Environment`, for the reason `ShowInChecklistButton` gives: menu content is
// built outside the presenting view's own tree, so anything it expects to find
// in the environment has to be captured by the view that owns the menu.

import CoreData
import SwiftUI

/// Who else has the same work as this one.
struct SameWorkPeersMenu: View {
    let work: CDWorkModel
    let context: NSManagedObjectContext

    var body: some View {
        WorkPeersMenu(
            title: "Who Else Has This Work",
            empty: "No one else has this work",
            list: WorkPeers.others(doing: work, in: context)
        )
    }
}

/// Who has work on this lesson.
struct LessonWorkPeersMenu: View {
    let lessonID: UUID
    let context: NSManagedObjectContext

    var body: some View {
        WorkPeersMenu(
            title: "Who Has Work on This",
            empty: "No one has work on this lesson",
            list: WorkPeers.children(workingOn: lessonID, in: context)
        )
    }
}

/// The list itself.
///
/// An empty answer is a plain line in the menu rather than a submenu with
/// nothing in it: "nobody" is the answer to the question, and the guide should
/// not have to hover into an empty menu to read it.
private struct WorkPeersMenu: View {
    let title: String
    let empty: String
    let list: WorkPeerList

    var body: some View {
        if list.isEmpty {
            // A disabled button rather than a bare `Text`: only a control is
            // certain to draw as a menu item, and an answer that silently does
            // not appear reads as a broken menu.
            Button(empty) {}
                .disabled(true)
        } else {
            Menu {
                ForEach(list.peers) { peer in
                    Button {
                        reveal(peer)
                    } label: {
                        Label(
                            "\(peer.name) — \(peer.detail)",
                            systemImage: peer.needsAttention
                                ? "exclamationmark.triangle"
                                : "person.crop.circle"
                        )
                    }
                    .disabled(peer.workID == nil)
                }
                if list.finishedCount > 0 {
                    Divider()
                    // Disabled: finished work has left the workspace, so there
                    // is nowhere to send the guide — but she should still know
                    // who got through it.
                    Button(
                        list.finishedCount == 1
                            ? "1 has finished it"
                            : "\(list.finishedCount) have finished it"
                    ) {}
                        .disabled(true)
                }
            } label: {
                Label(title, systemImage: "person.2")
            }
        }
    }

    /// Puts her copy on screen. The workspace works out which half and which
    /// pill actually holds the record, so a peer resting until next week is
    /// revealed under Scheduled rather than looked for under Needs Checking.
    private func reveal(_ peer: WorkPeer) {
        guard let workID = peer.workID else { return }
        AppRouter.shared.navigateToLessonsAndWork(workID: workID, preferredKind: .work)
    }
}
