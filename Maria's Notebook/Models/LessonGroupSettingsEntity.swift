import Foundation
import CoreData

@objc(CDLessonGroupSettings)
public class CDLessonGroupSettings: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var subject: String
    @NSManaged public var group: String
    @NSManaged public var requiresPractice: Bool
    @NSManaged public var requiresTeacherConfirmation: Bool
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?

    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "LessonGroupSettings", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.subject = ""
        self.group = ""
        self.requiresPractice = true
        self.requiresTeacherConfirmation = true
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}

// MARK: - Lookup

extension CDLessonGroupSettings {
    /// Finds group settings for a given subject+group pair.
    @MainActor
    static func find(
        subject: String,
        group: String,
        context: NSManagedObjectContext
    ) -> CDLessonGroupSettings? {
        let req = CDFetchRequest(CDLessonGroupSettings.self)
        req.predicate = NSPredicate(
            format: "subject ==[c] %@ AND group ==[c] %@",
            subject, group
        )
        req.fetchLimit = 1
        return context.safeFetchFirst(req)
    }
}
