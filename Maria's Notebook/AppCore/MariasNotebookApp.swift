//
//  MariasNotebookApp.swift
//  Maria's Notebook
//
//  Created by Danny De Berry on 11/26/25.
//

import SwiftUI
import SwiftData
import CoreData
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
    @State private var bootstrapper = AppBootstrapper.shared
    @State private var appRouter = AppRouter.shared
    @State private var databaseErrorCoordinator = DatabaseErrorCoordinator.shared
    @State private var dependencies: AppDependencies
    @State private var saveCoordinator: SaveCoordinator
    @State private var restoreCoordinator: RestoreCoordinator

    #if os(macOS)
    @NSApplicationDelegateAdaptor private var appDelegate: AutoBackupAppDelegate
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
        _saveCoordinator = State(wrappedValue: SaveCoordinator(toastService: deps.toastService))
        _restoreCoordinator = State(wrappedValue: RestoreCoordinator(appRouter: deps.appRouter))
    }

    // MARK: - Computed Properties

    /// Legacy accessor — kept during transition while views still use @Query / .modelContainer.
    /// Will be removed when all views are converted to @FetchRequest in Phase 4.
    @MainActor
    var sharedModelContainer: ModelContainer {
        AppBootstrapping.getSharedModelContainer()
    }
    
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
    
    // MARK: - Scene
    
    var body: some Scene {
        WindowGroup("", id: "mainWindow") {
            let logger = Logger.app(category: "App")
            // swiftlint:disable:next redundant_discardable_let
            let _ = logger.info("App body: Starting scene body evaluation")
            let stateDesc = String(describing: bootstrapper.state)
            // swiftlint:disable:next redundant_discardable_let
            let _ = logger.info("App body: bootstrapper state: \(stateDesc)")
            
            Group {
                // Show database error view if there's an initialization error
                if databaseErrorCoordinator.error != nil || AppBootstrapping.initError != nil {
                    DatabaseErrorView(errorCoordinator: databaseErrorCoordinator, appRouter: appRouter)
                } else {
                    // NORMAL APP FLOW
                    if bootstrapper.state == .ready {
                        Group {
                            if restoreCoordinator.isRestoring {
                                VStack(spacing: 20) {
                                    ProgressView().controlSize(.large)
                                    Text("Restoring data…")
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.clear)
                            } else if !hasCompletedOnboarding {
                                OnboardingView()
                            } else {
                                RootView()
                                    .environment(\.managedObjectContext, coreDataStack.viewContext)
                                    .environment(\.calendar, AppCalendar.shared)
                                    .environment(\.appRouter, appRouter)
                                    .environment(\.dependencies, dependencies)
                                    .environment(saveCoordinator)
                                    .environment(restoreCoordinator)
                            }
                        }
                    } else {
                        // Loading / Splash Screen
                        VStack(spacing: 20) {
                            ProgressView()
                                .controlSize(.large)
                            Text(loadingMessage)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.clear)
                    }
                }
            }
            .task {
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
                    appDelegate.setModelContainer(sharedModelContainer)
                    #endif
                    await bootstrapper.bootstrap(coreDataStack: coreDataStack)

                    // Configure CloudKit sync status monitoring
                    // NOTE: Still uses legacy ModelContainer during transition.
                    // Will be converted to use CoreDataStack in Phase 3B.
                    CloudKitSyncStatusService.shared.configure(with: sharedModelContainer)

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
                }
            }
            #if os(macOS)
            .modifier(OpenWindowOnNotificationModifier())
            #endif
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)
        .defaultSize(width: 800, height: 700)
        #endif
        .modelContainer(sharedModelContainer)
        .commands {
            // 1. STANDARD "NEW" ITEMS (File > New)
            // Consolidates all creation actions into the standard location
            CommandGroup(replacing: .newItem) {
                #if os(macOS)
                Button("New Window") {
                    NotificationCenter.default.post(name: .openNewWindow, object: nil)
                }
                Divider()
                #endif
                
                Button("New Lesson") { appRouter.requestNewLesson() }
                    .keyboardShortcut("n", modifiers: [.command])
                
                Button("New Student") { appRouter.requestNewStudent() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                
                Button("New Work…") { appRouter.requestNewWork() }
                    .keyboardShortcut("n", modifiers: [.command, .option])
            }

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
                    
                    Button("Restore Data…") { appRouter.requestRestoreBackup() }
                        .keyboardShortcut("b", modifiers: [.command, .shift])
                }
            }

            // 3. WINDOW MANAGEMENT & SEARCH
            #if os(macOS)
            CommandGroup(after: .windowSize) {
                Button("Close Window") {
                    NSApplication.shared.keyWindow?.close()
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            CommandGroup(after: .textEditing) {
                Button("Find…") {
                    NotificationCenter.default.post(name: .focusSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
            }
            #endif

            // 4. GO MENU (Navigation)
            // Dedicated menu for navigating between app sections
            CommandMenu("Go") {
                Button("Today") { appRouter.navigateTo(.today) }
                    .keyboardShortcut("1", modifiers: .command)

                Button("Presentations") { appRouter.navigateTo(.planningAgenda) }
                    .keyboardShortcut("2", modifiers: .command)

                Button("Students") { appRouter.navigateTo(.students) }
                    .keyboardShortcut("3", modifiers: .command)

                Button("Lessons") { appRouter.navigateTo(.lessons) }
                    .keyboardShortcut("4", modifiers: .command)

                Button("Logs") { appRouter.navigateTo(.logs) }
                    .keyboardShortcut("5", modifiers: .command)

                Button("Attendance") { appRouter.navigateTo(.attendance) }
                    .keyboardShortcut("6", modifiers: .command)
            }
            
            // 4. STANDARD SETTINGS (App Menu)
            // Maps the standard macOS "Settings..." menu item (Cmd+,) to your Settings tab
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    appRouter.navigateTo(.settings)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            // 5. HELP & TROUBLESHOOTING (Help Menu)
            CommandGroup(replacing: .help) {
                #if os(macOS)
                Button("Keyboard Shortcuts") {
                    NotificationCenter.default.post(name: .openKeyboardShortcutsWindow, object: nil)
                }
                .keyboardShortcut("/", modifiers: [.command])
                #endif

                Button("\(Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "App") Help") {
                    // Action to open help
                }
                .keyboardShortcut("?", modifiers: [.command])

                Divider()

                // Move all technical toggles into a submenu to keep the top bar clean
                Menu("Troubleshooting") {
                    #if os(macOS)
                    Toggle("Allow Local Store Fallback", isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: UserDefaultsKeys.allowLocalStoreFallback) },
                        set: { UserDefaults.standard.set($0, forKey: UserDefaultsKeys.allowLocalStoreFallback) }
                    ))
                    Toggle("Enable CloudKit Sync", isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: UserDefaultsKeys.enableCloudKitSync) },
                        set: { UserDefaults.standard.set($0, forKey: UserDefaultsKeys.enableCloudKitSync) }
                    ))
                    #endif
                    
                    Button("Use In-Memory Store Next Launch") {
                        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.useInMemoryStoreOnce)
                    }
                    
                    #if DEBUG
                    Divider()

                    Button("Reset Local Database…", role: .destructive) {
                        #if os(macOS)
                        AppBootstrapping.requestResetLocalDatabaseWithConfirmation()
                        #else
                        // On iOS, this would need a different approach (not available via menu)
                        do {
                            try AppBootstrapping.resetLocalDatabaseInDebug()
                        } catch {
                            Self.logger.warning("Failed to reset local database: \(error)")
                        }
                        #endif
                    }
                    #endif
                }
            }
        }

        #if os(macOS)
        WindowGroup("", id: "WorkDetailWindow", for: UUID.self) { $workID in
            if let id = workID {
                Group {
                    if restoreCoordinator.isRestoring {
                        VStack(spacing: 20) {
                            ProgressView().controlSize(.large)
                            Text("Restoring data…")
                                .foregroundStyle(.secondary)
                        }
                        .frame(minWidth: 400, minHeight: 300)
                    } else {
                        WorkDetailWindowHost(workID: id)
                            .environment(\.calendar, AppCalendar.shared)
                            .environment(saveCoordinator)
                            .environment(restoreCoordinator)
                    }
                }
            } else {
                Text("No work selected")
                    .frame(minWidth: 400, minHeight: 300)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)
        .defaultSize(width: 900, height: 700)
        .modelContainer(sharedModelContainer)

        // Student Detail Window
        WindowGroup("", id: "StudentDetailWindow", for: UUID.self) { $studentID in
            if let id = studentID {
                Group {
                    if restoreCoordinator.isRestoring {
                        VStack(spacing: 20) {
                            ProgressView().controlSize(.large)
                            Text("Restoring data…")
                                .foregroundStyle(.secondary)
                        }
                        .frame(minWidth: 400, minHeight: 300)
                    } else {
                        StudentDetailWindowHost(studentID: id)
                            .environment(\.calendar, AppCalendar.shared)
                            .environment(saveCoordinator)
                            .environment(restoreCoordinator)
                    }
                }
            } else {
                Text("No student selected")
                    .frame(minWidth: 400, minHeight: 300)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)
        .defaultSize(width: 860, height: 640)
        .modelContainer(sharedModelContainer)

        // Keyboard Shortcuts Help Window
        WindowGroup("Keyboard Shortcuts", id: "KeyboardShortcutsWindow") {
            KeyboardShortcutsHelpView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)
        .defaultSize(width: 480, height: 600)

        // Lesson Detail Window
        WindowGroup("", id: "LessonDetailWindow", for: UUID.self) { $lessonID in
            if let id = lessonID {
                Group {
                    if restoreCoordinator.isRestoring {
                        VStack(spacing: 20) {
                            ProgressView().controlSize(.large)
                            Text("Restoring data…")
                                .foregroundStyle(.secondary)
                        }
                        .frame(minWidth: 400, minHeight: 300)
                    } else {
                        LessonDetailWindowHost(lessonID: id)
                            .environment(\.calendar, AppCalendar.shared)
                            .environment(saveCoordinator)
                            .environment(restoreCoordinator)
                    }
                }
            } else {
                Text("No lesson selected")
                    .frame(minWidth: 400, minHeight: 300)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)
        .defaultSize(width: 720, height: 560)
        .modelContainer(sharedModelContainer)
        #endif
    }
}
