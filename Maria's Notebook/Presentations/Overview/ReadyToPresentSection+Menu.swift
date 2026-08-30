// ReadyToPresentSection+Menu.swift
// The presentation card's right-click menu, and the deletion behind it.
//
// Kept symmetrical with the work card's menu on purpose: the two halves of one
// screen should not disagree about whether right-clicking a selection acts on
// the selection. As there, the labels count the same targets the verbs use.
//
// Deleting a planned presentation cascades its `unifiedNotes`, so the
// confirmation says so — anything the guide wrote against the presentation
// goes with it.

import CoreData
import OSLog
import SwiftUI

extension ReadyToPresentSection {

    /// The presentations this menu acts on: this card, or the whole selection
    /// when this card is part of one.
    func menuTargets(for assignment: CDLessonAssignment) -> [CDLessonAssignment] {
        guard let id = assignment.id, selection.contains(id), selection.count > 1 else {
            return [assignment]
        }
        let visible = filteredAndSortedReadyLessons + filteredAndSortedBlockedLessons
        return visible.filter { selection.contains($0.id) }
    }

    @ViewBuilder
    func deleteButton(for assignment: CDLessonAssignment) -> some View {
        let targets = menuTargets(for: assignment)
        Button(role: .destructive) {
            pendingDeletion = targets
        } label: {
            Label(
                targets.count > 1 ? "Delete \(targets.count) Presentations…" : "Delete…",
                systemImage: "trash"
            )
        }
    }

    // MARK: - Confirmation

    var deletionTitle: String {
        pendingDeletion.count > 1
            ? "Delete \(pendingDeletion.count) presentations?"
            : "Delete this presentation?"
    }

    var deletionConfirmTitle: String {
        pendingDeletion.count > 1 ? "Delete \(pendingDeletion.count) Presentations" : "Delete"
    }

    var deletionMessage: String {
        let notes = pendingDeletion.reduce(into: 0) { total, assignment in
            total += assignment.unifiedNotes?.count ?? 0
        }
        let isMany = pendingDeletion.count > 1
        let subject = isMany ? "These planned presentations" : "This planned presentation"
        guard notes > 0 else {
            return subject + " will be removed. Lessons already given are not affected."
        }
        let noun = notes == 1 ? "note" : "notes"
        let pronoun = isMany ? "them" : "it"
        return subject + " and the \(notes) " + noun + " written on " + pronoun
            + " will be removed. This cannot be undone."
    }

    func performPendingDeletion() {
        for assignment in pendingDeletion {
            viewContext.delete(assignment)
        }
        do {
            try viewContext.save()
        } catch {
            Self.menuLogger.error("Failed to delete presentations: \(error)")
        }
        // Drop only what was destroyed — right-clicking an unselected card while
        // a selection is live must not throw the rest of the selection away.
        let deleted = Set(pendingDeletion.compactMap(\.id))
        let remaining = filteredAndSortedReadyLessons + filteredAndSortedBlockedLessons
        selection.retain(Set(remaining.compactMap(\.id)).subtracting(deleted))
        pendingDeletion = []
    }
}

// MARK: - The deep-link ring

extension View {
    /// The ring a deep link puts around the card it just revealed. Both card
    /// shapes drew this chain inline; they disagreed about nothing, so it is
    /// written once.
    @ViewBuilder
    func focusHighlight(_ isFocused: Bool) -> some View {
        overlay(
            RoundedRectangle(
                cornerRadius: UIConstants.CornerRadius.medium,
                style: .continuous
            )
            .stroke(Color.accentColor, lineWidth: isFocused ? 2.5 : 0)
            .shadow(color: .accentColor.opacity(isFocused ? 0.4 : 0), radius: 6)
        )
    }
}
