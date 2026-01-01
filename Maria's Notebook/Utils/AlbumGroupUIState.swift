import Foundation
import SwiftData

@Model
final class AlbumGroupUIState: Identifiable {
    @Attribute(.unique) var id: UUID
    var scopeKey: String
    var groupName: String  // exact group name (empty string represents ungrouped)
    var isCollapsed: Bool

    init(id: UUID = UUID(), scopeKey: String, groupName: String, isCollapsed: Bool = false) {
        self.id = id
        self.scopeKey = scopeKey
        self.groupName = groupName
        self.isCollapsed = isCollapsed
    }

    var normalizedGroupName: String {
        groupName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func displayName(for groupName: String) -> String {
        let trimmed = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(Ungrouped)" : trimmed
    }
}
