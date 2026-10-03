import SwiftUI

extension EnvironmentValues {
    /// True while the scene shows Sample Class, the local-only practice
    /// classroom. Screens use it to drop copy and history that belong to the
    /// guide's real, iCloud-synced class. Set by `activeClassroomEnvironment`.
    @Entry var isSampleClassroom = false

    /// The guide's own notebook's dependencies, whichever classroom the
    /// scene shows: what backup and restore act on. Nil in a scene that
    /// only ever shows her notebook (the Mac's Settings window), where
    /// `dependencies` is it.
    var notebookDependencies: AppDependencies? {
        get { self[NotebookDependenciesKey.self] }
        set { self[NotebookDependenciesKey.self] = newValue }
    }
}

private struct NotebookDependenciesKey: @preconcurrency EnvironmentKey {
    static let defaultValue: AppDependencies? = nil
}
