import SwiftUI

extension EnvironmentValues {
    /// True while the scene shows Sample Class, the local-only practice
    /// classroom. Screens use it to drop copy and history that belong to the
    /// guide's real, iCloud-synced class. Set by `activeClassroomEnvironment`.
    @Entry var isSampleClassroom = false
}
