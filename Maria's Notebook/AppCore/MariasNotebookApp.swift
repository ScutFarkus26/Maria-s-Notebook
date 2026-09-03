//
//  MariasNotebookApp.swift
//  Maria's Notebook
//
//  Created by Danny De Berry on 11/26/25.
//

import SwiftUI
import CoreData
import CloudKit
#if os(macOS)
import AppKit
#endif

@main
struct MariasNotebookApp: App {
    // MARK: - State Objects

    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase
    @State var bootstrapper = AppBootstrapper.shared
    @State var appRouter = AppRouter.shared
    @State var databaseErrorCoordinator = DatabaseErrorCoordinator.shared
    @State var dependencies: AppDependencies
    @State var classroomWorkspace: ClassroomWorkspaceStore
    @State var saveCoordinator: SaveCoordinator
    @State var restoreCoordinator: RestoreCoordinator

    #if os(macOS)
    @NSApplicationDelegateAdaptor var appDelegate: AutoBackupAppDelegate
    #elseif os(iOS)
    @UIApplicationDelegateAdaptor var appDelegate: ShareAcceptanceAppDelegate
    #endif

    // MARK: - Core Data Stack

    /// The shared Core Data stack — initialized once in init() and used by all scenes.
    let coreDataStack: CoreDataStack

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

    #if os(macOS)
    private var detailWindowDependencies: DetailWindowDependencies {
        DetailWindowDependencies(
            bootstrapper: bootstrapper,
            restoreCoordinator: restoreCoordinator,
            classroomWorkspace: classroomWorkspace,
            appRouter: appRouter,
            saveCoordinator: saveCoordinator
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
        #endif
        // Legacy .modelContainer removed — using CoreDataStack
        .commands {
            NotebookCommands(appRouter: appRouter, classroomWorkspace: classroomWorkspace)
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

        DetailWindowScene(
            id: "WorkDetailWindow", for: UUID.self, dependencies: detailWindowDependencies,
            defaultSize: CGSize(width: 900, height: 700), placeholder: .text("No work selected")
        ) { WorkDetailWindowHost(workID: $0) }

        DetailWindowScene(
            id: "StudentDetailWindow", for: UUID.self, dependencies: detailWindowDependencies,
            defaultSize: CGSize(width: 860, height: 640), placeholder: .text("No student selected")
        ) { StudentDetailWindowHost(studentID: $0) }

        // One album open on its own, e.g. dragged to a second display.
        DetailWindowScene(
            id: "AlbumWindow", for: String.self, dependencies: detailWindowDependencies,
            defaultSize: CGSize(width: 900, height: 900), placeholder: .text("No album selected")
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
            defaultSize: CGSize(width: 720, height: 560), placeholder: .text("No lesson selected")
        ) { LessonDetailWindowHost(lessonID: $0) }

        DetailWindowScene(
            id: "PresentationDetailWindow", for: UUID.self, dependencies: detailWindowDependencies,
            defaultSize: CGSize(width: 820, height: 720), placeholder: .text("No presentation selected")
        ) { PresentationDetailWindowHost(lessonAssignmentID: $0) }
        .centeredOnOpen()

        DetailWindowScene(
            id: "CommunityTopicWindow", for: UUID.self, dependencies: detailWindowDependencies,
            defaultSize: CGSize(width: 720, height: 760), minimumSize: CGSize(width: 500, height: 360),
            loadingStyle: .labeled,
            placeholder: .unavailable("No Topic Selected", systemImage: "bubble.left.and.bubble.right")
        ) { CommunityTopicWindowHost(topicID: $0) }

        DetailWindowScene(
            id: "ResourceDetailWindow", for: UUID.self, dependencies: detailWindowDependencies,
            defaultSize: CGSize(width: 760, height: 760), minimumSize: CGSize(width: 500, height: 360),
            loadingStyle: .labeled,
            placeholder: .unavailable("No Resource Selected", systemImage: "doc.text")
        ) { ResourceDetailWindowHost(resourceID: $0) }

        DetailWindowScene(
            id: "NoteEditorWindow", for: UUID.self, dependencies: detailWindowDependencies,
            defaultSize: CGSize(width: 700, height: 600), minimumSize: CGSize(width: 480, height: 320),
            loadingStyle: .labeled,
            placeholder: .unavailable("No Observation Selected", systemImage: "note.text", framed: false)
        ) { NoteEditorWindowHost(noteID: $0) }

        DetailWindowScene(
            id: "StudentReportWindow", for: UUID.self, dependencies: detailWindowDependencies,
            defaultSize: CGSize(width: 1000, height: 720), minimumSize: CGSize(width: 600, height: 420),
            loadingStyle: .labeled,
            placeholder: .unavailable("No Student Selected", systemImage: "person.crop.circle", framed: false)
        ) { StudentReportWindowHost(studentID: $0) }

        DetailWindowScene(
            id: "StudentDocumentsWindow", for: UUID.self, dependencies: detailWindowDependencies,
            defaultSize: CGSize(width: 760, height: 680), minimumSize: CGSize(width: 640, height: 480),
            loadingStyle: .labeled,
            placeholder: .unavailable("No Student Selected", systemImage: "paperclip")
        ) { StudentDocumentsWindowHost(studentID: $0) }

        DetailWindowScene(
            id: "MeetingSessionWindow", for: MeetingSessionWindowPayload.self,
            dependencies: detailWindowDependencies,
            defaultSize: CGSize(width: 1100, height: 760), minimumSize: CGSize(width: 700, height: 500),
            loadingStyle: .labeled,
            placeholder: .unavailable("No Meeting Selected", systemImage: "person.2", framed: false)
        ) { MeetingSessionWindowHost(payload: $0) }
        #endif
    }
}
