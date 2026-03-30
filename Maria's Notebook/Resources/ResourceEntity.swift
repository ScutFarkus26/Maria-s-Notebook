import Foundation
import CoreData

@objc(Resource)
public class CDResource: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var title: String
    @NSManaged public var descriptionText: String
    @NSManaged public var categoryRaw: String
    @NSManaged public var fileBookmark: Data?
    @NSManaged public var fileRelativePath: String
    @NSManaged public var fileSizeBytes: Int64
    @NSManaged public var thumbnailData: Data?
    @NSManaged public var tags: NSObject?  // Transformable [String]
    @NSManaged public var isFavorite: Bool
    @NSManaged public var lastViewedAt: Date?
    @NSManaged public var linkedLessonIDs: String
    @NSManaged public var linkedSubjects: String
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "Resource", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.title = ""
        self.descriptionText = ""
        self.categoryRaw = ResourceCategory.other.rawValue
        self.fileBookmark = nil
        self.fileRelativePath = ""
        self.fileSizeBytes = 0
        self.thumbnailData = nil
        self.tags = [] as NSArray
        self.isFavorite = false
        self.lastViewedAt = nil
        self.linkedLessonIDs = ""
        self.linkedSubjects = ""
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}

// MARK: - Enums

extension CDResource {
}

// MARK: - Computed Properties

extension CDResource {
    var category: ResourceCategory {
        get { ResourceCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    /// Access tags as a Swift [String] array
    var tagsArray: [String] {
        get { (tags as? [String]) ?? [] }
        set { tags = newValue as NSArray }
    }

    var fileSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }
}
