// WorkspaceMultiSelection.swift
// Command-click selection of several cards at once, for both halves of the
// Lessons & Work workspace.
//
// The workspace's whole scheduling gesture is "drag a card onto a day". That
// worked one card at a time, so giving five children the same lesson day, or
// clearing a morning's worth of checked work, was five separate drags.
//
// Command-click adds a card to the selection; a plain click clears it and does
// what a click always did. A selection is then a single drag — every selected
// card lands on the day you drop onto — and a single bulk action.
//
// Why the modifier is read from `NSEvent` rather than from a
// `TapGesture().modifiers(.command)`: that gesture modifier is macOS-only *and*
// composes with the card's existing open-on-tap gesture, which would open the
// detail window on the same click that extended the selection. Reading the
// flags inside the one tap handler keeps a single tap path with a single
// outcome.

import SwiftUI
#if os(macOS)
import AppKit
#endif

@Observable
final class WorkspaceMultiSelection {
    private(set) var ids: Set<UUID> = []

    init() {}

    var isEmpty: Bool { ids.isEmpty }
    var count: Int { ids.count }

    func contains(_ id: UUID?) -> Bool {
        guard let id else { return false }
        return ids.contains(id)
    }

    func toggle(_ id: UUID) {
        if ids.contains(id) {
            ids.remove(id)
        } else {
            ids.insert(id)
        }
    }

    func clear() {
        guard !ids.isEmpty else { return }
        ids = []
    }

    /// Drops anything no longer on screen. A selection that outlived its cards
    /// would keep a bulk action pointed at records the guide can no longer see.
    func retain(_ visible: Set<UUID>) {
        let kept = ids.intersection(visible)
        guard kept != ids else { return }
        ids = kept
    }

    /// True while the command key is down, so a tap handler can tell "add to
    /// the selection" from "open this one".
    static var isCommandHeld: Bool {
        #if os(macOS)
        NSEvent.modifierFlags.contains(.command)
        #else
        false
        #endif
    }

    /// Whether this platform offers the gesture at all. Command-click is a Mac
    /// gesture; elsewhere the cards behave exactly as they did.
    static var isAvailable: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    /// Resolves one tap on a card into what the guide meant by it.
    ///
    /// Returns `true` when the tap was taken as a selection change, so the
    /// caller knows not to also open the record.
    func handleTap(on id: UUID?) -> Bool {
        guard Self.isAvailable, let id else {
            clear()
            return false
        }
        guard Self.isCommandHeld else {
            clear()
            return false
        }
        toggle(id)
        return true
    }

    /// What a drag starting on `id` should carry.
    ///
    /// Dragging a selected card drags the whole selection; dragging an
    /// unselected one is still a single-card drag, and does not disturb the
    /// selection. The payloads are newline-joined —
    /// `UnifiedCalendarDragPayload.parseAll` reads them all back, and every
    /// older drop site that still calls `parse` takes the first line.
    func dragPayload(startingAt id: UUID, make: (UUID) -> UnifiedCalendarDragPayload) -> String {
        guard ids.contains(id), ids.count > 1 else {
            return make(id).stringRepresentation
        }
        // The dragged card leads, so a drop that orders by arrival puts the
        // card under the pointer where the guide aimed it.
        let rest = ids.subtracting([id]).sorted { $0.uuidString < $1.uuidString }
        return UnifiedCalendarDragPayload.joined(([id] + rest).map(make))
    }
}

// MARK: - The bar that appears while a selection is live

/// Shown above whichever grid the selection belongs to: what is selected, how
/// to act on it, and how to let it go.
struct WorkspaceSelectionBar<Actions: View>: View {
    let selection: WorkspaceMultiSelection
    let noun: String
    @ViewBuilder var actions: Actions

    var body: some View {
        if !selection.isEmpty {
            HStack(spacing: AppTheme.Spacing.small) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text("\(selection.count) \(noun)\(selection.count == 1 ? "" : "s") selected")
                    .font(.caption.weight(.semibold))
                Text("Drag any of them to put them all on a day")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                actions
                Button("Clear") { selection.clear() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.horizontal, AppTheme.Spacing.medium)
            .padding(.vertical, AppTheme.Spacing.verySmall)
            .background(Color.accentColor.opacity(UIConstants.OpacityConstants.veryFaint))
            .overlay(alignment: .bottom) { Divider() }
        }
    }
}

// MARK: - The ring on a selected card

extension View {
    /// Rings a card while it is part of the selection.
    ///
    /// Drawn as an overlay rather than a border so it sits outside the card's
    /// own stroke and cannot be mistaken for a status colour.
    @ViewBuilder
    func workspaceSelectionRing(_ isSelected: Bool, cornerRadius: CGFloat = 10) -> some View {
        overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 2.5)
            }
        }
        .background(
            isSelected ? Color.accentColor.opacity(UIConstants.OpacityConstants.veryFaint) : .clear,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }
}
