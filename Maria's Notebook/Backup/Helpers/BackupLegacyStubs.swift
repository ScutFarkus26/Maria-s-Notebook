// BackupLegacyStubs.swift
// Stub NSManagedObject subclasses for entities that existed in SwiftData
// but have no Core Data entity in the .xcdatamodeld.
// They exist only so backup import/export code compiles. No data is stored.

import Foundation
import CoreData

final class AlbumGroupOrder: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var albumID: String?
    @NSManaged var scopeKey: String?
    @NSManaged var groupName: String?
    @NSManaged var sortIndex: Int64
    @NSManaged var sortOrder: Int64
}

final class AlbumGroupUIState: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var albumID: String?
    @NSManaged var scopeKey: String?
    @NSManaged var groupName: String?
    @NSManaged var isCollapsed: Bool
    @NSManaged var isExpanded: Bool
}
