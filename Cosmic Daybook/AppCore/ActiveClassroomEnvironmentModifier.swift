import SwiftUI
import CoreData

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
