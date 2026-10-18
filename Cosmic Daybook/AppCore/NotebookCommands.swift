//
//  NotebookCommands.swift
//  Cosmic Daybook
//
//  The app's menu bar: File import/export, the Classroom and Go menus, and
//  Help. Key-window-targeted items live in AppCommands.swift and the album
//  reader's in AlbumsCommands.swift; this composes them in menu order.
//

import OSLog
import SwiftUI

struct NotebookCommands: Commands {
    private static let logger = Logger.app_

    let appRouter: AppRouter
    let notebookOpener: NotebookOpener

    /// Nil while the notebook's stores are still opening: the items that
    /// need it wait, disabled.
    private var classroomWorkspace: ClassroomWorkspaceStore? {
        notebookOpener.notebook?.classroomWorkspace
    }

    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif
    /// The key main window's actions, so Import Students… and the Go menu act
    /// in that window.
    @FocusedValue(\.quickCapture) private var quickCapture

    var body: some Commands {
        // 0. ALBUM READING COMMANDS
        // Inert unless an album view is frontmost — see AlbumsCommands.swift.
        AlbumsCommands()

        // 1. STANDARD "NEW" ITEMS (File > New)
        // Key-window-targeted via @FocusedValue — see AppCommands.swift.
        FileNewCommands()

        // 2. STANDARD "IMPORT/EXPORT" ITEMS (File > Import)
        // Moves Imports, Backups, and Restores here
        CommandGroup(replacing: .importExport) {
            Section {
                Button("Import Students…") { quickCapture?.importStudents() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                    .disabled(quickCapture == nil)
            }

            Section {
                // Backing up and restoring are Settings › Sync and backup's
                // job (its Back Up Now shows how it went); nothing handled the
                // routes these used to post. Not while the notebook couldn't be
                // opened: the error screen has its own way back.
                Button("Back Up…") { openSyncBackupSettings() }
                    .keyboardShortcut("b", modifiers: [.command])
                    .disabled(
                        classroomWorkspace?.isShowingSampleClass != false
                            || DatabaseErrorCoordinator.shared.error != nil
                    )

                Button("Restore Data…") { openSyncBackupSettings() }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                    .disabled(
                        classroomWorkspace?.isShowingSampleClass != false
                            || DatabaseErrorCoordinator.shared.error != nil
                    )
            }
        }

        // 3. WINDOW MANAGEMENT & SEARCH
        // NOTE: Close (⌘W) is supplied automatically by SwiftUI for WindowGroup
        // scenes — we no longer hand-roll it via NSApplication.keyWindow.
        // Find (⌘F) is key-window-targeted via @FocusedValue — see AppCommands.swift.
        FindCommands()

        // VIEW MENU — standard Show/Hide Sidebar (⌃⌘S) for the NavigationSplitView
        SidebarCommands()
        QuickCaptureButtonCommands()

        // The key main window's own, like the Go menu: a switch that would
        // lose an open sheet or detail window asks first, in that window.
        CommandMenu("Classroom") {
            Button("My Class") { quickCapture?.switchClassroom(to: .myClass) }
                .disabled(quickCapture == nil || classroomWorkspace.map { $0.selection == .myClass } ?? true)

            Button("Sample Class") { quickCapture?.switchClassroom(to: .sampleClass) }
                .disabled(
                    quickCapture == nil
                        || classroomWorkspace.map { $0.selection == .sampleClass || $0.isPreparingSample } ?? true
                )
        }

        // 4. GO MENU (Navigation)
        // Dedicated menu for navigating between app sections. The key main
        // window's own, like File › New: the shared router's switch was seen
        // by every window, so with two open a background one could move.
        CommandMenu("Go") {
            // Same order as the sidebar, most-used first. Each destination
            // in a collapsed group opens that group when chosen here.
            Button("Today") { quickCapture?.go(to: .today) }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(quickCapture == nil)

            Button("Attendance") { quickCapture?.go(to: .attendance) }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(quickCapture == nil)

            Button("Students") { quickCapture?.go(to: .students) }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(quickCapture == nil)

            Button("Lessons & Work") {
                quickCapture?.openLessonsAndWork(.init(scope: .attention, preferredKind: .work))
            }
            .keyboardShortcut("4", modifiers: .command)
            .disabled(quickCapture == nil)

            Button("Lessons") { quickCapture?.go(to: .lessons) }
                .keyboardShortcut("5", modifiers: .command)
                .disabled(quickCapture == nil)

            Button("Notes") { quickCapture?.go(to: .notes) }
                .keyboardShortcut("6", modifiers: .command)
                .disabled(quickCapture == nil)

            Button("Todos") { quickCapture?.go(to: .todos) }
                .keyboardShortcut("7", modifiers: .command)
                .disabled(quickCapture == nil)
        }

        // 5. HELP & TROUBLESHOOTING (Help Menu)
        CommandGroup(replacing: .help) {
            #if os(macOS)
            // Opens the window itself, so it works with no main window open
            // (bug hunt 2026-10-17 #36).
            Button("Keyboard Shortcuts") { openKeyboardShortcutsWindow() }
            .keyboardShortcut("/", modifiers: [.command])
            #endif

            // NOTE: A standard "<App> Help" item belongs here once real help
            // content exists (a hosted docs URL or Help Book). The previous
            // item performed no action and bound ⌘? — which macOS reserves for
            // the Help-menu search field — so it was removed rather than ship a no-op.

            // Engineering/diagnostics controls (local-store fallback, in-memory
            // store, iCloud-sync toggle) now live in Settings > Database > Advanced
            // and Data & Sync — not the user-facing Help menu.
            #if DEBUG
            Divider()

            Menu("Troubleshooting (Debug)") {
                Button("Reset Local Database…", role: .destructive) {
                    #if os(macOS)
                    AppBootstrapping.requestResetLocalDatabaseWithConfirmation()
                    #else
                    // Takes effect the next time the app opens.
                    if !AppBootstrapping.armLocalDatabaseResetInDebug() {
                        Self.logger.warning("Local database reset not armed: iCloud sync is off")
                    }
                    #endif
                }
            }
            #endif
        }
    }

    /// Settings › Sync and backup, where restore lives: the Mac's Settings
    /// window, or the Settings page.
    private func openSyncBackupSettings() {
        appRouter.showSyncBackupSettings()
        #if os(macOS)
        openSettings()
        #endif
    }
}
