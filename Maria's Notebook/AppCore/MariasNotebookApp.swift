//
//  MariasNotebookApp.swift
//  Maria's Notebook
//
//  Created by Danny De Berry on 11/26/25.
//

import SwiftUI
import CoreData
import CloudKit
import OSLog
import TipKit
#if os(macOS)
import AppKit
#endif

@main
// swiftlint:disable:next type_body_length
struct MariasNotebookApp: App {
    private static let logger = Logger.app_

    // MARK: - State Objects

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var bootstrapper = AppBootstrapper.shared
    @State private var appRouter = AppRouter.shared
    @State private var databaseErrorCoordinator = DatabaseErrorCoordinator.shared
    @State private var dependencies: AppDependencies
    @State private var classroomWorkspace: ClassroomWorkspaceStore
    @State private var saveCoordinator: SaveCoordinator
    @State private var restoreCoordinator: RestoreCoordinator

    #if os(macOS)
    @NSApplicationDelegateAdaptor private var appDelegate: AutoBackupAppDelegate
    #elseif os(iOS)
    @UIApplicationDelegateAdaptor private var appDelegate: ShareAcceptanceAppDelegate
    #endif

    // MARK: - Core Data Stack

    /// The shared Core Data stack — initialized once in init() and used by all scenes.
    private let coreDataStack: CoreDataStack

    // MARK: - Initialization

    init() {
        AppBootstrapping.performInitialSetup()
        let stack = AppBootstrapping.getSharedCoreDataStack()
        coreDataStack = stack
        let deps = AppDependencies(coreDataStack: stack)
        _dependencies = State(wrappedValue: deps)
        _classroomWorkspace = State(wrappedValue: ClassroomWorkspaceStore(
            primaryStack: stack,
            primaryDependencies: deps
        ))
        _saveCoordinator = State(wrappedValue: SaveCoordinator(toastService: deps.toastService))
        _restoreCoordinator = State(wrappedValue: RestoreCoordinator(appRouter: deps.appRouter))

        #if os(iOS)
        // BGTaskScheduler handlers must be registered before launch finishes.
        BackupBackgroundTaskManager.register(dependencies: deps, coreDataStack: stack)
        #endif
    }

    // MARK: - Computed Properties

    private var loadingMessage: String {
        switch bootstrapper.state {
        case .idle:
            return "Starting up..."
        case .initializingContainer:
            return "Initializing database..."
        case .migrating:
            return "Running migrations..."
        case .ready:
            return "Ready"
        }
    }
    
    // MARK: - App Flow Content

    @ViewBuilder
    private var appFlowContent: some View {
        if bootstrapper.state == .ready {
            readyContent
        } else {
            VStack(spacing: 20) {
                ProgressView()
                    .controlSize(.large)
                Text(loadingMessage)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
        }
    }

    @ViewBuilder
    private var readyContent: some View {
        if restoreCoordinator.isRestoring {
            VStack(spacing: 20) {
                ProgressView().controlSize(.large)
                Text("Restoring data…")
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
        } else if !hasCompletedOnboarding {
            OnboardingView()
        } else {
            RootView(classroomWorkspace: classroomWorkspace)
                .activeClassroomEnvironment(classroomWorkspace)
                .environment(\.calendar, AppCalendar.shared)
                .environment(\.appRouter, appRouter)
                .environment(saveCoordinator)
                .environment(restoreCoordinator)
                .environment(AlbumLibrary.shared)
                .syncingFromICloudOverlay()
        }
    }

    #if os(macOS)
    /// One album open on its own, e.g. dragged to a second display.
    private var albumWindowScene: some Scene {
        WindowGroup("", id: "AlbumWindow", for: String.self) { $albumID in
            albumWindowContent(albumID: albumID)
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .windowResizability(.automatic)
        .defaultSize(width: 900, height: 900)
    }

    @ViewBuilder
    private func albumWindowContent(albumID: String?) -> some View {
        if let albumID {
            if bootstrapper.state != .ready || restoreCoordinator.isRestoring {
                VStack(spacing: 20) {
                    ProgressView().controlSize(.large)
                    Text(restoreCoordinator.isRestoring ? "Restoring data…" : "Loading…")
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 400, minHeight: 300)
            } else {
                AlbumWindowHost(albumID: albumID)
                    .activeClassroomEnvironment(classroomWorkspace)
                    .environment(\.calendar, AppCalendar.shared)
                    .environment(\.appRouter, appRouter)
                    .environment(saveCoordinator)
                    .environment(restoreCoordinator)
                    .environment(AlbumLibrary.shared)
            }
        } else {
            Text("No album selected")
                .frame(minWidth: 400, minHeight: 300)
        }
    }
    #endif

    private var mainWindowContent: some View {
        let logger: Logger = Logger.app(category: "App")
        // swiftlint:disable:next redundant_discardable_let
        let _ = logger.info("App body: Starting scene body evaluation")
        let stateDesc: String = String(describing: bootstrapper.state)
        // swiftlint:disable:next redundant_discardable_let
        let _ = logger.info("App body: bootstrapper state: \(stateDesc)")

        return Group {
            if databaseErrorCoordinator.error != nil || AppBootstrapping.initError != nil {
                DatabaseErrorView(errorCoordinator: databaseErrorCoordinator, appRouter: appRouter)
            } else {
                appFlowContent
            }
        }
    }

    // MARK: - Startup

    private func performStartupBootstrap() async {
        // Sync initError to error coordinator if not already set
        if databaseErrorCoordinator.error == nil, let error = AppBootstrapping.initError {
            databaseErrorCoordinator.setError(error)
        }

        #if !os(macOS)
        // TipKit's root quick-action tip is temporarily disabled on macOS
        // because it can trigger a SwiftUI update loop when switching views.
        try? Tips.configure([
            .displayFrequency(.weekly)
        ])
        #endif

        // Only bootstrap if the store loaded successfully
        if AppBootstrapping.initError == nil {
            #if os(macOS)
            appDelegate.setCoreDataStack(coreDataStack, dependencies: dependencies)
            #endif
            await bootstrapper.bootstrap(coreDataStack: coreDataStack)

            // Configure CloudKit sync status monitoring
            CloudKitSyncStatusService.shared.configure(with: coreDataStack)

            // Register for remote notifications so CloudKit can push sync events.
            // NSPersistentCloudKitContainer handles incoming notifications
            // internally — we just need to ensure the app is registered.
            #if os(iOS)
            UIApplication.shared.registerForRemoteNotifications()
            #elseif os(macOS)
            NSApplication.shared.registerForRemoteNotifications()
            #endif

            // PERFORMANCE: Start memory pressure monitoring
            // This allows the app to proactively clear caches before being terminated
            _ = dependencies.memoryPressureMonitor

            // Start the interval auto-backup loop (no-op unless the user
            // enabled scheduled backups). This also hands the manager its
            // context so toggling the setting later can restart the loop.
            dependencies.autoBackupManager.startScheduledBackups(viewContext: coreDataStack.viewContext)

            // Index students + lessons into Spotlight (searchable + Siri-referenceable); idempotent, off critical path.
            Task { await SpotlightIndexer.reindexAll() }

            #if os(macOS)
            // Start the MCP server for Claude Desktop if the teacher enabled it.
            MCPServerService.shared.applySettings()
            #endif
        }
    }

    // MARK: - Scene Phase

    /// iOS/iPadOS auto-backup trigger: the app rarely "quits" on iOS, so the
    /// move to the background is the data-protection moment. The backup is
    /// change-gated (persistent history), so idle backgrounding costs nothing.
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        #if os(iOS)
        guard phase == .background,
              bootstrapper.state == .ready,
              AppBootstrapping.initError == nil else { return }

        let assertion = BackgroundTaskAssertion()
        assertion.begin(named: "AutoBackup")
        Task { @MainActor in
            await BackupBackgroundTaskManager.schedule()
            await dependencies.autoBackupManager.performBackgroundBackup(
                viewContext: coreDataStack.viewContext
            )
            assertion.end()
        }
        #endif
    }

    // MARK: - Scene

    var body: some Scene {
        WindowGroup("", id: "mainWindow") {
            mainWindowContent
            .task {
                guard !AppBootstrapping.isRunningUnitTests else { return }
                await performStartupBootstrap()
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChange(newPhase)
            }
            #if os(macOS)
            .modifier(OpenWindowOnNotificationModifier())
            #endif
        }
        #if os(macOS)
        .windowToolbarStyle(.unified(showsTitle: true))
        .windowResizability(.automatic)
        // Default must be >= the enforced minimum (900x600, see EnsureResizableWindow)
        // so a freshly-opened window isn't immediately snapped wider.
        .defaultSize(width: 1000, height: 720)
        #endif
        // Legacy .modelContainer removed — using CoreDataStack
        .commands {
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

                Button("Lessons & Work") { appRouter.navigateToLessonsAndWork(.needsAttention) }
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

        #if os(macOS)
        Settings {
            Group {
                if bootstrapper.state == .ready,
                   !restoreCoordinator.isRestoring,
                   hasCompletedOnboarding {
                    SettingsView(showsPageHeader: false)
                        .environment(\.managedObjectContext, coreDataStack.viewContext)
                        .environment(\.calendar, AppCalendar.shared)
                        .environment(\.appRouter, appRouter)
                        .environment(\.dependencies, dependencies)
                        .environment(saveCoordinator)
                        .environment(restoreCoordinator)
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.small)
                        Text(settingsUnavailableMessage)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 760, minHeight: 600)
        }

        Window("Notebook Companion", id: "notebookCompanion") {
            if bootstrapper.state == .ready,
               !restoreCoordinator.isRestoring,
               hasCompletedOnboarding {
                DesktopNotebookCompanionView()
                    .activeClassroomEnvironment(classroomWorkspace)
                    .environment(\.calendar, AppCalendar.shared)
                    .environment(\.appRouter, appRouter)
                    .environment(saveCoordinator)
                    .environment(restoreCoordinator)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 88, height: 88)
            }
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)
        .defaultSize(width: 88, height: 88)

        WindowGroup("", id: "WorkDetailWindow", for: UUID.self) { $workID in
            if let id = workID {
                Group {
                    if bootstrapper.state != .ready || restoreCoordinator.isRestoring {
                        VStack(spacing: 20) {
                            ProgressView().controlSize(.large)
                            Text(restoreCoordinator.isRestoring ? "Restoring data…" : "Loading…")
                                .foregroundStyle(.secondary)
                        }
                        .frame(minWidth: 400, minHeight: 300)
                    } else {
                        WorkDetailWindowHost(workID: id)
                            .activeClassroomEnvironment(classroomWorkspace)
                            .environment(\.calendar, AppCalendar.shared)
                            .environment(\.appRouter, appRouter)
                            .environment(saveCoordinator)
                            .environment(restoreCoordinator)
                    }
                }
            } else {
                Text("No work selected")
                    .frame(minWidth: 400, minHeight: 300)
            }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .windowResizability(.automatic)
        .defaultSize(width: 900, height: 700)
        // Legacy .modelContainer removed — using CoreDataStack

        // CDStudent Detail Window
        WindowGroup("", id: "StudentDetailWindow", for: UUID.self) { $studentID in
            if let id = studentID {
                Group {
                    if bootstrapper.state != .ready || restoreCoordinator.isRestoring {
                        VStack(spacing: 20) {
                            ProgressView().controlSize(.large)
                            Text(restoreCoordinator.isRestoring ? "Restoring data…" : "Loading…")
                                .foregroundStyle(.secondary)
                        }
                        .frame(minWidth: 400, minHeight: 300)
                    } else {
                        StudentDetailWindowHost(studentID: id)
                            .activeClassroomEnvironment(classroomWorkspace)
                            .environment(\.calendar, AppCalendar.shared)
                            .environment(\.appRouter, appRouter)
                            .environment(saveCoordinator)
                            .environment(restoreCoordinator)
                    }
                }
            } else {
                Text("No student selected")
                    .frame(minWidth: 400, minHeight: 300)
            }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .windowResizability(.automatic)
        .defaultSize(width: 860, height: 640)
        // Legacy .modelContainer removed — using CoreDataStack

        albumWindowScene

        // Keyboard Shortcuts Help Window
        WindowGroup("Keyboard Shortcuts", id: "KeyboardShortcutsWindow") {
            KeyboardShortcutsHelpView()
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .windowResizability(.automatic)
        .defaultSize(width: 480, height: 600)

        // CDLesson Detail Window
        WindowGroup("", id: "LessonDetailWindow", for: UUID.self) { $lessonID in
            if let id = lessonID {
                Group {
                    if bootstrapper.state != .ready || restoreCoordinator.isRestoring {
                        VStack(spacing: 20) {
                            ProgressView().controlSize(.large)
                            Text(restoreCoordinator.isRestoring ? "Restoring data…" : "Loading…")
                                .foregroundStyle(.secondary)
                        }
                        .frame(minWidth: 400, minHeight: 300)
                    } else {
                        LessonDetailWindowHost(lessonID: id)
                            .activeClassroomEnvironment(classroomWorkspace)
                            .environment(\.calendar, AppCalendar.shared)
                            .environment(\.appRouter, appRouter)
                            .environment(saveCoordinator)
                            .environment(restoreCoordinator)
                    }
                }
            } else {
                Text("No lesson selected")
                    .frame(minWidth: 400, minHeight: 300)
            }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .windowResizability(.automatic)
        .defaultSize(width: 720, height: 560)
        // Legacy .modelContainer removed — using CoreDataStack

        WindowGroup("", id: "PresentationDetailWindow", for: UUID.self) { $lessonAssignmentID in
            if let id = lessonAssignmentID {
                Group {
                    if bootstrapper.state != .ready || restoreCoordinator.isRestoring {
                        VStack(spacing: 20) {
                            ProgressView().controlSize(.large)
                            Text(restoreCoordinator.isRestoring ? "Restoring data…" : "Loading…")
                                .foregroundStyle(.secondary)
                        }
                        .frame(minWidth: 400, minHeight: 300)
                    } else {
                        PresentationDetailWindowHost(lessonAssignmentID: id)
                            .activeClassroomEnvironment(classroomWorkspace)
                            .environment(\.calendar, AppCalendar.shared)
                            .environment(\.appRouter, appRouter)
                            .environment(saveCoordinator)
                            .environment(restoreCoordinator)
                    }
                }
            } else {
                Text("No presentation selected")
                    .frame(minWidth: 400, minHeight: 300)
            }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .windowResizability(.automatic)
        .defaultSize(width: 820, height: 720)
        // Legacy .modelContainer removed — using CoreDataStack

        WindowGroup("", id: "CommunityTopicWindow", for: UUID.self) { $topicID in
            if let id = topicID {
                if bootstrapper.state != .ready || restoreCoordinator.isRestoring {
                    ProgressView(restoreCoordinator.isRestoring ? "Restoring data…" : "Loading…")
                        .frame(minWidth: 500, minHeight: 360)
                } else {
                    CommunityTopicWindowHost(topicID: id)
                        .activeClassroomEnvironment(classroomWorkspace)
                        .environment(\.calendar, AppCalendar.shared)
                        .environment(\.appRouter, appRouter)
                        .environment(saveCoordinator)
                        .environment(restoreCoordinator)
                }
            } else {
                ContentUnavailableView("No Topic Selected", systemImage: "bubble.left.and.bubble.right")
                    .frame(minWidth: 500, minHeight: 360)
            }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .windowResizability(.automatic)
        .defaultSize(width: 720, height: 760)

        WindowGroup("", id: "ResourceDetailWindow", for: UUID.self) { $resourceID in
            if let id = resourceID {
                if bootstrapper.state != .ready || restoreCoordinator.isRestoring {
                    ProgressView(restoreCoordinator.isRestoring ? "Restoring data…" : "Loading…")
                        .frame(minWidth: 500, minHeight: 360)
                } else {
                    ResourceDetailWindowHost(resourceID: id)
                        .activeClassroomEnvironment(classroomWorkspace)
                        .environment(\.calendar, AppCalendar.shared)
                        .environment(\.appRouter, appRouter)
                        .environment(saveCoordinator)
                        .environment(restoreCoordinator)
                }
            } else {
                ContentUnavailableView("No Resource Selected", systemImage: "doc.text")
                    .frame(minWidth: 500, minHeight: 360)
            }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .windowResizability(.automatic)
        .defaultSize(width: 760, height: 760)

        WindowGroup("", id: "NoteEditorWindow", for: UUID.self) { $noteID in
            if let id = noteID {
                if bootstrapper.state != .ready || restoreCoordinator.isRestoring {
                    ProgressView(restoreCoordinator.isRestoring ? "Restoring data…" : "Loading…")
                        .frame(minWidth: 480, minHeight: 320)
                } else {
                    NoteEditorWindowHost(noteID: id)
                        .activeClassroomEnvironment(classroomWorkspace)
                        .environment(\.calendar, AppCalendar.shared)
                        .environment(\.appRouter, appRouter)
                        .environment(saveCoordinator)
                        .environment(restoreCoordinator)
                }
            } else {
                ContentUnavailableView("No Observation Selected", systemImage: "note.text")
            }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .windowResizability(.automatic)
        .defaultSize(width: 700, height: 600)

        WindowGroup("", id: "StudentReportWindow", for: UUID.self) { $studentID in
            if let id = studentID {
                if bootstrapper.state != .ready || restoreCoordinator.isRestoring {
                    ProgressView(restoreCoordinator.isRestoring ? "Restoring data…" : "Loading…")
                        .frame(minWidth: 600, minHeight: 420)
                } else {
                    StudentReportWindowHost(studentID: id)
                        .activeClassroomEnvironment(classroomWorkspace)
                        .environment(\.calendar, AppCalendar.shared)
                        .environment(\.appRouter, appRouter)
                        .environment(saveCoordinator)
                        .environment(restoreCoordinator)
                }
            } else {
                ContentUnavailableView("No Student Selected", systemImage: "person.crop.circle")
            }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .windowResizability(.automatic)
        .defaultSize(width: 1000, height: 720)

        WindowGroup("", id: "StudentDocumentsWindow", for: UUID.self) { $studentID in
            if let id = studentID {
                if bootstrapper.state != .ready || restoreCoordinator.isRestoring {
                    ProgressView(restoreCoordinator.isRestoring ? "Restoring data…" : "Loading…")
                        .frame(minWidth: 640, minHeight: 480)
                } else {
                    StudentDocumentsWindowHost(studentID: id)
                        .activeClassroomEnvironment(classroomWorkspace)
                        .environment(\.calendar, AppCalendar.shared)
                        .environment(\.appRouter, appRouter)
                        .environment(saveCoordinator)
                        .environment(restoreCoordinator)
                }
            } else {
                ContentUnavailableView("No Student Selected", systemImage: "paperclip")
                    .frame(minWidth: 640, minHeight: 480)
            }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .windowResizability(.automatic)
        .defaultSize(width: 760, height: 680)

        WindowGroup("", id: "MeetingSessionWindow", for: MeetingSessionWindowPayload.self) { $payload in
            if let payload {
                if bootstrapper.state != .ready || restoreCoordinator.isRestoring {
                    ProgressView(restoreCoordinator.isRestoring ? "Restoring data…" : "Loading…")
                        .frame(minWidth: 700, minHeight: 500)
                } else {
                    MeetingSessionWindowHost(payload: payload)
                        .activeClassroomEnvironment(classroomWorkspace)
                        .environment(\.calendar, AppCalendar.shared)
                        .environment(\.appRouter, appRouter)
                        .environment(saveCoordinator)
                        .environment(restoreCoordinator)
                }
            } else {
                ContentUnavailableView("No Meeting Selected", systemImage: "person.2")
            }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .windowResizability(.automatic)
        .defaultSize(width: 1100, height: 760)
        #endif
    }

    #if os(macOS)
    private var settingsUnavailableMessage: String {
        if restoreCoordinator.isRestoring {
            return "Settings will be available when the restore finishes."
        }
        if !hasCompletedOnboarding {
            return "Finish setup in the main window to use Settings."
        }
        return loadingMessage
    }
    #endif
}
