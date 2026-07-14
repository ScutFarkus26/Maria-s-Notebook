//  AppCommands.swift
//  Maria's Notebook
//
//  Menu-bar commands that must act on the KEY window's content.
//
//  These use @FocusedValue instead of NotificationCenter posts or shared-router
//  Bool flags so that a command targets exactly one window — the key one — and
//  is disabled when no main window is frontmost (e.g. only a detail window is
//  open, or all windows are closed). This avoids three failure modes of the
//  broadcast approach: the same sheet opening in every main window at once,
//  commands firing into a background window while a detail window is key, and
//  one-shot trigger flags being stranded `true` with no observer alive.

import SwiftUI

/// Quick-capture actions the key main window exposes to the menu bar.
/// Mirrors `PieMenuAction` so File > New and the radial quick-command menu
/// always offer the same set.
struct QuickCaptureActions {
    let newPresentation: () -> Void
    let recordPractice: () -> Void
    let newTodo: () -> Void
    let newNote: () -> Void
}

/// A stable, per-window target for the standard Find command.
///
/// Keeping the callback inside this reference type lets the focused-value
/// system compare the target by identity. The command still acts only on the
/// key main window, just as it did when the callback was stored directly.
@MainActor
final class FocusedSearchAction {
    private var action: (() -> Void)?

    func setAction(_ action: @escaping () -> Void) {
        self.action = action
    }

    func clearAction() {
        action = nil
    }

    func invoke() {
        action?()
    }
}

extension FocusedValues {
    /// Provided by the key main window's RootView; nil when no main window is key.
    @Entry var quickCapture: QuickCaptureActions?
    /// Opens the app-wide search UI in the key main window.
    @Entry var openSearch: FocusedSearchAction?
}

/// File > New — standard creation commands plus the quick-capture actions.
struct FileNewCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.quickCapture) private var quickCapture

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            #if os(macOS)
            // Direct openWindow (not a notification) so this works even when
            // zero windows are open and never spawns more than one window.
            Button("New Window") { openWindow(id: "mainWindow") }
                .keyboardShortcut("n", modifiers: [.command, .control])
            Divider()
            #endif

            // Ellipsis per HIG: each of these opens a sheet needing further input.
            Button("New Lesson…") { AppRouter.shared.requestNewLesson() }
                .keyboardShortcut("n", modifiers: [.command])

            Button("New Student…") { AppRouter.shared.requestNewStudent() }
                .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("New Work…") { AppRouter.shared.requestNewWork() }
                .keyboardShortcut("n", modifiers: [.command, .option])

            Divider()

            // Quick-capture — same actions as the floating radial menu. Disabled
            // when no main window is key (the closures live on RootView).
            Button("New Presentation…") { quickCapture?.newPresentation() }
                .keyboardShortcut("p", modifiers: [.command, .control])
                .disabled(quickCapture == nil)

            Button("Record Practice…") { quickCapture?.recordPractice() }
                .keyboardShortcut("r", modifiers: [.command, .control])
                .disabled(quickCapture == nil)

            Button("New Todo…") { quickCapture?.newTodo() }
                .keyboardShortcut("t", modifiers: [.command, .control])
                .disabled(quickCapture == nil)

            Button("New Note…") { quickCapture?.newNote() }
                .keyboardShortcut("k", modifiers: [.command, .control])
                .disabled(quickCapture == nil)
        }
    }
}

/// Edit-menu Find… routed to the key main window's global search.
struct FindCommands: Commands {
    @FocusedValue(\.openSearch) private var openSearch

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            #if os(macOS)
            Button("Find…") { openSearch?.invoke() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(openSearch == nil)
            #endif
        }
    }
}
