import CoreData
import Foundation
import OSLog
import SwiftUI

/// The classroom whose records are currently shown by the app.
enum ClassroomWorkspace: String, CaseIterable, Identifiable, Sendable {
    case myClass
    case sampleClass

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .myClass: "My Class"
        case .sampleClass: "Sample Class"
        }
    }

    var systemImage: String {
        switch self {
        case .myClass: "person.3.fill"
        case .sampleClass: "testtube.2"
        }
    }
}

/// Owns the two independent classroom sessions and swaps the environment used
/// by app views. Sample Class is deliberately local-only and has its own SQLite
/// file; it cannot upload, fetch, edit, or delete records in My Class.
@Observable
final class ClassroomWorkspaceStore {
    private static let logger = Logger.classroomWorkspace

    let primaryStack: CoreDataStack
    let primaryDependencies: AppDependencies

    private(set) var selection: ClassroomWorkspace = .myClass
    private(set) var isPreparingSample = false
    private(set) var preparationErrorMessage: String?

    private var sampleStack: CoreDataStack?
    private var sampleDependencies: AppDependencies?

    /// Whether a sheet, or a detail window that holds typing, is open anywhere
    /// (`OpenEditorsCheck`); tests pass their own.
    @ObservationIgnored private let hasOpenEditors: () -> Bool
    /// Where the Sample Class keeps its records; nil is the app's own file
    /// (`CoreDataStack.sampleClassroomStoreURL()`), and tests pass a scratch one.
    @ObservationIgnored private let sampleStoreURL: URL?

    init(
        primaryStack: CoreDataStack,
        primaryDependencies: AppDependencies,
        hasOpenEditors: @escaping () -> Bool = { OpenEditorsCheck.anyOpen() },
        sampleStoreURL: URL? = nil
    ) {
        self.primaryStack = primaryStack
        self.primaryDependencies = primaryDependencies
        self.hasOpenEditors = hasOpenEditors
        self.sampleStoreURL = sampleStoreURL
    }

    var isShowingSampleClass: Bool { selection == .sampleClass }

    /// What asking for a classroom leads to.
    enum SwitchRequest: Equatable {
        /// Nothing open would be lost: switch at once.
        case switchNow
        /// A sheet, or a detail window that holds typing, is open: ask first,
        /// and switch only on Switch.
        case askFirst
    }

    /// Whether choosing `workspace` switches at once or asks first. A switch
    /// rebuilds every main window and closes every detail window, so while a
    /// sheet, or a detail window that holds typing, is open anywhere it asks
    /// first (bug hunt 2026-10-17 #31). Choosing the classroom already showing rebuilds
    /// nothing (Sample Class only refreshes its lessons), so that never asks.
    func switchRequest(to workspace: ClassroomWorkspace) -> SwitchRequest {
        guard workspace != selection, hasOpenEditors() else { return .switchNow }
        return .askFirst
    }

    /// Puts up "Switch classroom?" and hands Switch back as `proceed`; Cancel
    /// never calls it.
    typealias AskBeforeSwitching = @MainActor (_ proceed: @escaping @MainActor () async -> Void) -> Void

    /// The one way the app's classroom controls switch: at once while nothing
    /// is open that the switch would lose, else only once `ask` hands back
    /// Switch (bug hunt 2026-10-17 #31).
    func requestSwitch(to workspace: ClassroomWorkspace, ask: @escaping AskBeforeSwitching) async {
        switch switchRequest(to: workspace) {
        case .switchNow:
            await select(workspace, askingIfOpened: ask)
        case .askFirst:
            // Switch was chosen knowing what's open, so it isn't asked twice.
            ask { [weak self] in await self?.select(workspace, askingIfOpened: nil) }
        }
    }

    var activeStack: CoreDataStack {
        if selection == .sampleClass, let sampleStack {
            return sampleStack
        }
        return primaryStack
    }

    var activeDependencies: AppDependencies {
        if selection == .sampleClass, let sampleDependencies {
            return sampleDependencies
        }
        return primaryDependencies
    }

    /// Shows `workspace`. Choosing the Sample Class while it shows refreshes
    /// its lessons. `ask`, when given, is asked before a switch to the Sample
    /// Class that something opened while it was being prepared would lose.
    private func select(_ workspace: ClassroomWorkspace, askingIfOpened ask: AskBeforeSwitching?) async {
        guard workspace != selection || workspace == .sampleClass else { return }

        if workspace == .myClass {
            selection = .myClass
            LessonFileStorage.showingSampleClass = nil
            return
        }

        guard !isPreparingSample else { return }
        isPreparingSample = true
        preparationErrorMessage = nil
        defer { isPreparingSample = false }

        // Give SwiftUI a chance to display the preparation indicator before
        // Core Data opens the local store and mirrors the lesson catalog.
        await Task.yield()

        do {
            let destinationStack: CoreDataStack
            if let sampleStack {
                destinationStack = sampleStack
            } else {
                let newStack = try CoreDataStack(
                    enableCloudKit: false,
                    localStoreURL: sampleStoreURL ?? CoreDataStack.sampleClassroomStoreURL(),
                    managedObjectModel: primaryStack.container.managedObjectModel
                )
                sampleStack = newStack
                sampleDependencies = AppDependencies(coreDataStack: newStack, isSampleClassroom: true)
                destinationStack = newStack
            }

            try SampleClassroomSeeder.prepare(
                lessonsFrom: primaryStack.viewContext,
                sampleContext: destinationStack.viewContext
            )
            // File › New…, the Mac's toolbar and menus and other windows stay
            // live while "Preparing Sample Class…" is up, so something opened
            // meanwhile is asked about before the switch loses it (review c #9).
            if let ask, selection != .sampleClass, hasOpenEditors() {
                ask { [weak self] in self?.showSampleClass() }
                return
            }
            showSampleClass()
        } catch {
            preparationErrorMessage = Self.samplePreparationFailedMessage
            Self.logger.error("Could not prepare Sample Class: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Shows the Sample Class, once its store is prepared.
    private func showSampleClass() {
        guard let sampleStack else { return }
        selection = .sampleClass
        // Its lessons use the real notebook's files: while it shows, a change
        // there (Claude's, over MCP) keeps the ones it uses.
        LessonFileStorage.showingSampleClass = sampleStack.viewContext
        Self.logger.info("Switched to isolated Sample Class")
    }

    /// The alert's message when the sample class can't be set up (the raw error goes to the log).
    static let samplePreparationFailedMessage = "The sample class couldn't be set up. Try again, or restart the app."

    func dismissPreparationError() {
        preparationErrorMessage = nil
    }
}
