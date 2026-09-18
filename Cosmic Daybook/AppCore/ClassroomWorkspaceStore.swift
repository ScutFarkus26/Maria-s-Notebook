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
    private static let logger = Logger.app(category: "ClassroomWorkspace")

    let primaryStack: CoreDataStack
    let primaryDependencies: AppDependencies

    private(set) var selection: ClassroomWorkspace = .myClass
    private(set) var isPreparingSample = false
    private(set) var preparationErrorMessage: String?

    private var sampleStack: CoreDataStack?
    private var sampleDependencies: AppDependencies?

    init(primaryStack: CoreDataStack, primaryDependencies: AppDependencies) {
        self.primaryStack = primaryStack
        self.primaryDependencies = primaryDependencies
    }

    var isShowingSampleClass: Bool { selection == .sampleClass }

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

    func select(_ workspace: ClassroomWorkspace) async {
        guard workspace != selection || workspace == .sampleClass else { return }

        if workspace == .myClass {
            selection = .myClass
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
                    localStoreURL: CoreDataStack.sampleClassroomStoreURL(),
                    managedObjectModel: primaryStack.container.managedObjectModel
                )
                sampleStack = newStack
                sampleDependencies = AppDependencies(coreDataStack: newStack)
                destinationStack = newStack
            }

            try SampleClassroomSeeder.prepare(
                lessonsFrom: primaryStack.viewContext,
                sampleContext: destinationStack.viewContext
            )
            selection = .sampleClass
            Self.logger.info("Switched to isolated Sample Class")
        } catch {
            preparationErrorMessage = error.localizedDescription
            Self.logger.error("Could not prepare Sample Class: \(error.localizedDescription)")
        }
    }

    func dismissPreparationError() {
        preparationErrorMessage = nil
    }
}

/// Applies the currently selected classroom's Core Data context and dependency
/// graph to a scene. Resetting identity is intentional: fetch requests, view
/// models, and sheet state must not carry objects across classroom boundaries.
private struct ActiveClassroomEnvironmentModifier: ViewModifier {
    let workspaceStore: ClassroomWorkspaceStore

    func body(content: Content) -> some View {
        content
            .environment(\.managedObjectContext, workspaceStore.activeStack.viewContext)
            .environment(\.dependencies, workspaceStore.activeDependencies)
            // Keep identity outside the environment replacements so every
            // @FetchRequest controller is discarded before the new context is used.
            .id(workspaceStore.selection)
    }
}

extension View {
    func activeClassroomEnvironment(_ workspaceStore: ClassroomWorkspaceStore) -> some View {
        modifier(ActiveClassroomEnvironmentModifier(workspaceStore: workspaceStore))
    }
}
