//
//  NotebookCommands.swift
//  Maria's Notebook
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
    let classroomWorkspace: ClassroomWorkspaceStore

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
                Button("Import Lessons…") { appRouter.requestImportLessons() }
                    .keyboardShortcut("i", modifiers: [.command])

                Button("Import Students…") { appRouter.requestImportStudents() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
            }

            Section {
                Button("Create Backup") { appRouter.requestCreateBackup() }
                    .keyboardShortcut("b", modifiers: [.command])
                    .disabled(classroomWorkspace.isShowingSampleClass)

                Button("Restore Data…") { appRouter.requestRestoreBackup() }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                    .disabled(classroomWorkspace.isShowingSampleClass)
            }
        }

        // 3. WINDOW MANAGEMENT & SEARCH
        // NOTE: Close (⌘W) is supplied automatically by SwiftUI for WindowGroup
        // scenes — we no longer hand-roll it via NSApplication.keyWindow.
        // Find (⌘F) is key-window-targeted via @FocusedValue — see AppCommands.swift.
        FindCommands()

        // VIEW MENU — standard Show/Hide Sidebar (⌃⌘S) for the NavigationSplitView
        SidebarCommands()
        NotebookCompanionCommands()

        CommandMenu("Classroom") {
            Button("My Class") {
                Task { await classroomWorkspace.select(.myClass) }
            }
            .disabled(classroomWorkspace.selection == .myClass)

            Button("Sample Class") {
                Task { await classroomWorkspace.select(.sampleClass) }
            }
            .disabled(
                classroomWorkspace.selection == .sampleClass
                    || classroomWorkspace.isPreparingSample
            )
        }

        // 4. GO MENU (Navigation)
        // Dedicated menu for navigating between app sections
        CommandMenu("Go") {
            Button("Today") { appRouter.navigateTo(.today) }
                .keyboardShortcut("1", modifiers: .command)

            Button("Lessons & Work") { appRouter.navigateToLessonsAndWork(.attention, preferredKind: .work) }
                .keyboardShortcut("2", modifiers: .command)

            Button("Students") { appRouter.navigateTo(.students) }
                .keyboardShortcut("3", modifiers: .command)

            Button("Lessons") { appRouter.navigateTo(.lessons) }
                .keyboardShortcut("4", modifiers: .command)

            Button("Logs") { appRouter.navigateTo(.logs) }
                .keyboardShortcut("5", modifiers: .command)

            Button("Attendance") { appRouter.navigateTo(.attendance) }
                .keyboardShortcut("6", modifiers: .command)

            Button("Stories") { appRouter.navigateTo(.stories) }
                .keyboardShortcut("7", modifiers: .command)
        }

        // 5. HELP & TROUBLESHOOTING (Help Menu)
        CommandGroup(replacing: .help) {
            #if os(macOS)
            Button("Keyboard Shortcuts") {
                NotificationCenter.default.post(name: .openKeyboardShortcutsWindow, object: nil)
            }
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
                    do {
                        try AppBootstrapping.resetLocalDatabaseInDebug()
                    } catch {
                        Self.logger.warning("Failed to reset local database: \(error)")
                    }
                    #endif
                }
            }
            #endif
        }
    }
}
