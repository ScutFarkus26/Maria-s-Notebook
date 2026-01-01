import Foundation
import SwiftData

@Model
final class AlbumGroupOrder: Identifiable {
    @Attribute(.unique) var id: UUID
    var scopeKey: String   // e.g., subject key used to scope album lessons
    var groupName: String  // exact group name (empty string represents ungrouped)
    var sortIndex: Int     // 0-based order among groups for this scope

    init(id: UUID = UUID(), scopeKey: String, groupName: String, sortIndex: Int = 0) {
        self.id = id
        self.scopeKey = scopeKey
        self.groupName = groupName
        self.sortIndex = sortIndex
    }

    var normalizedGroupName: String {
        groupName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func displayName(for groupName: String) -> String {
        let trimmed = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(Ungrouped)" : trimmed
    }
}
