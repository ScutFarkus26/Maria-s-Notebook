import Foundation
import CoreData

@objc(CDDocument)
public class CDDocument: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var title: String
    @NSManaged public var category: String
    @NSManaged public var uploadDate: Date?
    @NSManaged public var pdfData: Data?
    @NSManaged public var pdfFileBookmark: Data?
    @NSManaged public var pdfFileRelativePath: String

    // MARK: - Cross-Store Foreign Key
    @NSManaged public var studentID: String?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "Document", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.title = ""
        self.category = ""
        self.uploadDate = Date()
        self.pdfData = nil
        self.pdfFileBookmark = nil
        self.pdfFileRelativePath = ""
    }
}

// MARK: - Cross-Store Relationship Accessor

extension CDDocument {
    var student: CDStudent? {
        get {
            guard let studentID, let ctx = managedObjectContext else { return nil }
            guard let uuid = UUID(uuidString: studentID) else { return nil }
            return ctx.object(CDStudent.self, id: uuid)
        }
        set { studentID = newValue?.id?.uuidString }
    }
}
