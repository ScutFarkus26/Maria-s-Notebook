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
