//
//  CosmicDaybookApp+Notebook.swift
//  Cosmic Daybook
//
//  What the app builds on the notebook's stack: its dependencies, the
//  classroom workspace and the services launcher. The stack's stores open
//  off the main thread (`AppBootstrapping.sharedCoreDataStack()`), so these
//  are made once they have, not in the App's init; until then the window
//  says "Opening your notebook…".
//

import Observation

/// The notebook's stack and the app-wide objects built on it, made once per
/// process when its stores are open (`NotebookOpener`).
final class OpenNotebook {
    let coreDataStack: CoreDataStack
    let dependencies: AppDependencies
    let classroomWorkspace: ClassroomWorkspaceStore
    /// Starts the app-wide services once per process (see
    /// `CosmicDaybookApp.startAppServicesIfNeeded`).
    let servicesLauncher: AppServicesLauncher

    /// One coordinator app-wide: the environment instance every view saves
    /// through must be the one `dependencies.saveCoordinator` hands out, or
    /// failures recorded on one never reach the other's "Couldn't Save" alert.
    var saveCoordinator: SaveCoordinator { dependencies.saveCoordinator }

    init(coreDataStack: CoreDataStack) {
        let dependencies = AppDependencies(coreDataStack: coreDataStack)
        self.coreDataStack = coreDataStack
        self.dependencies = dependencies
        classroomWorkspace = ClassroomWorkspaceStore(
            primaryStack: coreDataStack,
            primaryDependencies: dependencies
        )
        servicesLauncher = AppServicesLauncher(
            coreDataStack: coreDataStack,
            dependencies: dependencies,
            bootstrapper: AppBootstrapper.shared
        )
    }
}

/// Opens the notebook once per process and keeps what was built on it, for
/// every scene, the menus and the app delegates. Observed: what waits for it
/// (the main window, Settings, the detail windows, the menus) updates when
/// it opens.
@Observable
final class NotebookOpener {
    static let shared = NotebookOpener()

    /// The open notebook; nil while its stores are still opening.
    private(set) var notebook: OpenNotebook?

    private init() {}

    /// Starts opening the notebook, without waiting. `CosmicDaybookApp.init`
    /// calls it, so the stores start opening at launch.
    func start() {
        Task { _ = await open() }
    }

    /// The open notebook, waiting for its stores if they're still opening.
    func open() async -> OpenNotebook {
        if let notebook { return notebook }
        let stack = await AppBootstrapping.sharedCoreDataStack()
        // Another caller may have built it while this one waited.
        if let notebook { return notebook }
        let opened = OpenNotebook(coreDataStack: stack)
        notebook = opened
        return opened
    }
}
