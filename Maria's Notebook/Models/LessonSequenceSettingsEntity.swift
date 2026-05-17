import Foundation
import CoreData

@objc(CDLessonSequenceSettings)
public class CDLessonSequenceSettings: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var area: String
    @NSManaged public var sequence: String
    @NSManaged public var requiresPractice: Bool
    @NSManaged public var requiresTeacherConfirmation: Bool
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?

    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "LessonSequenceSettings", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.area = ""
        self.sequence = ""
        self.requiresPractice = true
        self.requiresTeacherConfirmation = true
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}

// MARK: - Lookup

extension CDLessonSequenceSettings {
    /// Finds sequence settings for a given area+sequence pair.
    @MainActor
    static func find(
        area: String,
        sequence: String,
        context: NSManagedObjectContext
    ) -> CDLessonSequenceSettings? {
        let req = CDFetchRequest(CDLessonSequenceSettings.self)
        req.predicate = NSPredicate(
            format: "area ==[c] %@ AND sequence ==[c] %@",
            area, sequence
        )
        req.fetchLimit = 1
        return context.safeFetchFirst(req)
    }
}
