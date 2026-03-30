import Foundation
import CoreData

@objc(Document)
public class Document: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var title: String
    @NSManaged public var category: String
    @NSManaged public var uploadDate: Date?
    @NSManaged public var pdfData: Data?

    // MARK: - Relationships
    @NSManaged public var student: Student?

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
    }
}
