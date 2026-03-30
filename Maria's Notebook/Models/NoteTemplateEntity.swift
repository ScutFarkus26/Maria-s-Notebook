import Foundation
import CoreData

@objc(NoteTemplateEntity)
public class NoteTemplateEntity: NSManagedObject {
    // MARK: - Attributes
    @NSManaged public var id: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var title: String
    @NSManaged public var body: String
    @NSManaged public var categoryRaw: String
    // Transformable [String] array stored as NSObject? in Core Data
    @NSManaged public var tags: NSObject?
    @NSManaged public var sortOrder: Int64
    @NSManaged public var isBuiltIn: Bool

    // MARK: - Convenience Init
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "NoteTemplate", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.createdAt = Date()
        self.title = ""
        self.body = ""
        self.categoryRaw = NoteCategory.general.rawValue
        self.tags = nil
        self.sortOrder = 0
        self.isBuiltIn = false
    }
}

// MARK: - Computed Properties
extension NoteTemplateEntity {
    /// Legacy category field -- kept for migration; new code uses `tags`
    var category: NoteCategory {
        get { NoteCategory(rawValue: categoryRaw) ?? .general }
        set { categoryRaw = newValue.rawValue }
    }

    /// The legacy categoryRaw value (read-only, for migration)
    var legacyCategoryRaw: String { categoryRaw }

    /// Typed accessor for tags Transformable
    var tagsArray: [String] {
        get { tags as? [String] ?? [] }
        set { tags = newValue as NSObject }
    }
}
