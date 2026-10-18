//
//  CosmicDaybookApp.swift
//  Cosmic Daybook
//
//  Created by Danny De Berry on 11/26/25.
//

import SwiftUI
import UserNotifications
import CoreData
import CloudKit
#if os(macOS)
import AppKit
#endif

@main
struct CosmicDaybookApp: App {
    // MARK: - State Objects

    @AppStorage(UserDefaultsKeys.hasCompletedOnboarding) var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase
    @State var bootstrapper = AppBootstrapper.shared
    @State var appRouter = AppRouter.shared
    @State var databaseErrorCoordinator = DatabaseErrorCoordinator.shared
    /// The notebook's stack and what is built on it, once its stores are open.
    @State var notebookOpener = NotebookOpener.shared
    @State var restoreCoordinator: RestoreCoordinator

    #if os(macOS)
    @NSApplicationDelegateAdaptor var appDelegate: AutoBackupAppDelegate
    #elseif os(iOS)
    @UIApplicationDelegateAdaptor var appDelegate: ShareAcceptanceAppDelegate
    #endif

    #if os(macOS)
    /// `.suppressed` only for an MCP-only launch (the Claude bridge started
    /// the app; see `AppLaunchMode`), so it comes up with no main window;
    /// `.automatic` — SwiftUI's default — for every other launch.
    let mainWindowLaunchBehavior: SceneLaunchBehavior
    #endif

    // MARK: - Initialization

    init() {
        let appInit = LaunchSignposts.begin("AppInit")
        defer { LaunchSignposts.end("AppInit", appInit) }

        #if os(macOS)
        // Before any window exists: the toolbar NaN assertion has to be caught
        // on the main thread, and this is the first main-thread code we own.
        ToolbarLayoutAssertionGuard.install()
        mainWindowLaunchBehavior = AppLaunchMode.current == .mcpOnly ? .suppressed : .automatic
        #endif

        AppBootstrapping.performInitialSetup()
        // Before launch finishes, so a tapped reminder that launched the app
        // is delivered (the front-desk email's opens Attendance).
        UNUserNotificationCenter.current().delegate = NotebookNotificationTaps.shared
        restoreCoordinator = RestoreCoordinator(appRouter: AppRouter.shared)

        // The stores open off the main thread while the window says "Opening
        // your notebook…"; what needs them waits for them (`NotebookOpener`,
        // `AppBootstrapping.sharedCoreDataStack()`). Started here, before any
        // scene, so a launch that brings up none (a background intent) opens
        // them too, and on a background thread at once, not once the main
        // actor is through setting up the first window.
        AppBootstrapping.startOpeningStores()
        NotebookOpener.shared.start()

        #if os(iOS)
        // BGTaskScheduler handlers must be registered before launch finishes;
        // the handler waits for the notebook itself.
        BackupBackgroundTaskManager.register(notebook: { await NotebookOpener.shared.open() })
        #endif
    }

    #if os(macOS)
    private var detailWindowDependencies: DetailWindowDependencies {
        DetailWindowDependencies(
            bootstrapper: bootstrapper,
            restoreCoordinator: restoreCoordinator,
            notebookOpener: notebookOpener,
            appRouter: appRouter
        )
    }
    #endif

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
        .defaultLaunchBehavior(mainWindowLaunchBehavior)
        #endif
        .commands {
            NotebookCommands(appRouter: appRouter, notebookOpener: notebookOpener)
            #if os(macOS)
            MainWindowOpenerCommands()
            #endif
        }

        #if os(macOS)
        Settings {
            Group {
                if bootstrapper.state == .ready,
                   !restoreCoordinator.isRestoring,
                   hasCompletedOnboarding,
                   let notebook = notebookOpener.notebook {
                    SettingsView(showsPageHeader: false)
                        .environment(\.managedObjectContext, notebook.coreDataStack.viewContext)
                        .environment(\.calendar, AppCalendar.shared)
                        .environment(\.appRouter, appRouter)
                        .environment(\.dependencies, notebook.dependencies)
                        .environment(notebook.saveCoordinator)
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

        // countsAsEditor: windows that hold typing (work, a presentation, a
        // topic, an observation, a report, a meeting), so a classroom switch
        // asks before closing them; the rest close without asking (review c #12).
        DetailWindowScene(
            id: "WorkDetailWindow", for: UUID.self, dependencies: detailWindowDependencies,
            defaultSize: CGSize(width: 900, height: 700), placeholder: .text("No work selected"),
            countsAsEditor: true
        ) { WorkDetailWindowHost(workID: $0) }

        DetailWindowScene(
            id: "StudentDetailWindow", for: UUID.self, dependencies: detailWindowDependencies,
            defaultSize: CGSize(width: 860, height: 640), placeholder: .text("No student selected"),
            countsAsEditor: false
        ) { StudentDetailWindowHost(studentID: $0) }

        // One album open on its own, e.g. dragged to a second display.
        DetailWindowScene(
            id: "AlbumWindow", for: String.self, dependencies: detailWindowDependencies,
            defaultSize: CGSize(width: 900, height: 900), placeholder: .text("No album selected"),
            countsAsEditor: false
        ) { AlbumWindowHost(albumID: $0).environment(AlbumLibrary.shared) }

        // Keyboard Shortcuts Help Window
        WindowGroup("Keyboard Shortcuts", id: "KeyboardShortcutsWindow") {
            KeyboardShortcutsHelpView()
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .windowResizability(.automatic)
        .defaultSize(width: 480, height: 600)

        DetailWindowScene(
            id: "LessonDetailWindow", for: UUID.self, dependencies: detailWindowDependencies,
            defaultSize: CGSize(width: 720, height: 560), placeholder: .text("No lesson selected"),
            countsAsEditor: false
        ) { LessonDetailWindowHost(lessonID: $0) }

        DetailWindowScene(
            id: "PresentationDetailWindow", for: UUID.self, dependencies: detailWindowDependencies,
            defaultSize: CGSize(width: 820, height: 720), placeholder: .text("No presentation selected"),
            countsAsEditor: true
        ) { PresentationDetailWindowHost(lessonAssignmentID: $0) }
        .centeredOnOpen()

        DetailWindowScene(
            id: "CommunityTopicWindow", for: UUID.self, dependencies: detailWindowDependencies,
            defaultSize: CGSize(width: 720, height: 760), minimumSize: CGSize(width: 500, height: 360),
            loadingStyle: .labeled,
            placeholder: .unavailable("No Topic Selected", systemImage: "bubble.left.and.bubble.right"),
            countsAsEditor: true
        ) { CommunityTopicWindowHost(topicID: $0) }

        DetailWindowScene(
            id: "ResourceDetailWindow", for: UUID.self, dependencies: detailWindowDependencies,
            defaultSize: CGSize(width: 760, height: 760), minimumSize: CGSize(width: 500, height: 360),
            loadingStyle: .labeled,
            placeholder: .unavailable("No Resource Selected", systemImage: "doc.text"),
            countsAsEditor: false
        ) { ResourceDetailWindowHost(resourceID: $0) }

        DetailWindowScene(
            id: "NoteEditorWindow", for: UUID.self, dependencies: detailWindowDependencies,
            defaultSize: CGSize(width: 700, height: 600), minimumSize: CGSize(width: 480, height: 320),
            loadingStyle: .labeled,
            placeholder: .unavailable("No Observation Selected", systemImage: "note.text", framed: false),
            countsAsEditor: true
        ) { NoteEditorWindowHost(noteID: $0) }

        DetailWindowScene(
            id: "StudentReportWindow", for: UUID.self, dependencies: detailWindowDependencies,
            defaultSize: CGSize(width: 1000, height: 720), minimumSize: CGSize(width: 600, height: 420),
            loadingStyle: .labeled,
            placeholder: .unavailable("No Student Selected", systemImage: "person.crop.circle", framed: false),
            countsAsEditor: true
        ) { StudentReportWindowHost(studentID: $0) }

        DetailWindowScene(
            id: "StudentDocumentsWindow", for: UUID.self, dependencies: detailWindowDependencies,
            defaultSize: CGSize(width: 760, height: 680), minimumSize: CGSize(width: 640, height: 480),
            loadingStyle: .labeled,
            placeholder: .unavailable("No Student Selected", systemImage: "paperclip"),
            countsAsEditor: false
        ) { StudentDocumentsWindowHost(studentID: $0) }

        DetailWindowScene(
            id: "MeetingSessionWindow", for: MeetingSessionWindowPayload.self,
            dependencies: detailWindowDependencies,
            defaultSize: CGSize(width: 1100, height: 760), minimumSize: CGSize(width: 700, height: 500),
            loadingStyle: .labeled,
            placeholder: .unavailable("No Meeting Selected", systemImage: "person.2", framed: false),
            countsAsEditor: true
        ) { MeetingSessionWindowHost(payload: $0) }
        #endif
    }
}
