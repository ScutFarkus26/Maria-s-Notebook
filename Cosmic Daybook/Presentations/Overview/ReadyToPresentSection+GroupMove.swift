// ReadyToPresentSection+GroupMove.swift
// A child's chip on a ready lesson moves her between that lesson's groups:
// right-click on the Mac, long-press on iPad, "Move to Group N" for each
// other group and "Move to a New Group" when her group has others in it.
//
// The write is `PresentationGroupMove`, the same path a chip dragged onto
// another group takes, so her notes and year-plan entries go with her and a
// group she leaves empty is folded away. The toast offers Undo, as Presented
// Today does. Merge Groups… stays the other way to the same result.
//
// The whole line is still the drag source for the calendar; the chip only
// adds a menu. Whether a long-press on iPad opens the menu rather than
// lifting the line is undocumented, so it is a by-hand device check.

import CoreData
import SwiftUI

/// One item in a chip's move menu.
struct BacklogChipMove: Identifiable {
    /// The group to move to; nil for a new one.
    let target: CDLessonAssignment?
    /// "Group 2", or nil for a new group.
    let groupNumber: Int?

    var id: String { groupNumber.map { "group-\($0)" } ?? "new" }

    var title: String {
        groupNumber.map { "Move to Group \($0)" } ?? "Move to a New Group"
    }

    /// The same, as a VoiceOver action on the line: "Move Ada L to Group 2".
    func spokenTitle(for name: String) -> String {
        groupNumber.map { "Move \(name) to Group \($0)" } ?? "Move \(name) to a New Group"
    }
}

extension ReadyToPresentSection {

    /// What `chip`'s menu offers on line `la`, one of `groups` (the lesson's
    /// groups in this list, in their numbered order). Ready lessons only:
    /// a brewing or given one is not regrouped from here.
    func chipMoves(
        for chip: BacklogChip,
        on la: CDLessonAssignment,
        groups: [CDLessonAssignment],
        visibleChildren: Int,
        context: BacklogRenderContext
    ) -> [BacklogChipMove] {
        guard context.state != .waitingForWork, context.state != .followUp, !la.isGiven else { return [] }
        let childID = chip.id.uuidString
        var moves: [BacklogChipMove] = groups.enumerated().compactMap { index, group in
            guard group.objectID != la.objectID, !group.isGiven,
                  !group.studentIDs.contains(childID) else { return nil }
            return BacklogChipMove(target: group, groupNumber: index + 1)
        }
        // A lone child would only be moved into a copy of her own group.
        if visibleChildren > 1, la.studentIDs.count > 1 {
            moves.append(BacklogChipMove(target: nil, groupNumber: nil))
        }
        return moves
    }

    /// The chip, with its move menu when it has one. A chip with nothing to
    /// offer gets no menu at all, so a long-press there does nothing new.
    @ViewBuilder
    func movableChip(
        _ chip: BacklogChip,
        on la: CDLessonAssignment,
        moves: [BacklogChipMove],
        longWaitColor: Color
    ) -> some View {
        let base = BacklogStudentChip(chip: chip, longWaitColor: longWaitColor)
        if moves.isEmpty {
            base
        } else {
            base.contextMenu { chipMoveMenu(chip, on: la, moves: moves) }
        }
    }

    /// One level of submenu at most: past three groups, the group moves sit
    /// under "Move to Group".
    @ViewBuilder
    private func chipMoveMenu(_ chip: BacklogChip, on la: CDLessonAssignment, moves: [BacklogChipMove]) -> some View {
        let groupMoves = moves.filter { $0.target != nil }
        let newGroup = moves.first { $0.target == nil }
        if groupMoves.count > 3 {
            Menu("Move to Group", systemImage: "arrow.right.circle") {
                ForEach(groupMoves) { move in
                    Button("Group \(move.groupNumber ?? 0)") { moveChild(chip, from: la, move: move) }
                }
            }
        } else {
            ForEach(groupMoves) { move in
                Button(move.title, systemImage: "arrow.right.circle") { moveChild(chip, from: la, move: move) }
            }
        }
        if let newGroup {
            Button(newGroup.title, systemImage: "plus.circle") { moveChild(chip, from: la, move: newGroup) }
        }
    }

    // MARK: - The write

    func moveChild(_ chip: BacklogChip, from la: CDLessonAssignment, move: BacklogChipMove) {
        var receipt: PresentationGroupMove.Receipt?
        let saved = saveCoordinator.saveEdit(in: viewContext, reason: "Move a child between groups") {
            if let target = move.target {
                receipt = PresentationGroupMove.move(chip.id, from: la, to: target, in: viewContext)
            } else {
                receipt = PresentationGroupMove.moveToNewGroup(chip.id, from: la, in: viewContext)
            }
        }
        guard saved else {
            dependencies.toastService.showError("Couldn't move \(chip.name). Try again.")
            return
        }
        // Nil only when the groups changed under the menu; nothing was written.
        guard let receipt else { return }
        PresentationDetailUtilities.notifyInboxRefresh()
        let destination = move.groupNumber.map { "Group \($0)" } ?? "a new group"
        dependencies.toastService.show(
            "Moved \(chip.name) to \(destination).",
            type: .success,
            duration: 6,
            undoAction: { undoChildMove(receipt, name: chip.name) }
        )
    }

    private func undoChildMove(_ receipt: PresentationGroupMove.Receipt, name: String) {
        let saved = saveCoordinator.saveEdit(in: viewContext, reason: "Undo moving a child between groups") {
            guard PresentationGroupMove.undo(receipt, in: viewContext) else { throw GroupMoveUndoRefused() }
        }
        guard saved else {
            dependencies.toastService.showError("Couldn't move \(name) back. Try Merge Groups… instead.")
            return
        }
        PresentationDetailUtilities.notifyInboxRefresh()
    }
}

/// The groups changed after the move (the child moved again, or a group was
/// given or deleted), so Undo leaves them as they are.
private struct GroupMoveUndoRefused: Error {}
