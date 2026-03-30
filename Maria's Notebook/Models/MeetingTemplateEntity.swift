import Foundation
import CoreData

@objc(MeetingTemplateEntity)
public class CDMeetingTemplateEntity: NSManagedObject {
    // MARK: - Attributes
    @NSManaged public var id: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var name: String
    @NSManaged public var reflectionPrompt: String
    @NSManaged public var focusPrompt: String
    @NSManaged public var requestsPrompt: String
    @NSManaged public var guideNotesPrompt: String
    @NSManaged public var sortOrder: Int64
    @NSManaged public var isActive: Bool
    @NSManaged public var isBuiltIn: Bool

    // MARK: - Convenience Init
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "MeetingTemplate", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.createdAt = Date()
        self.name = ""
        self.reflectionPrompt = ""
        self.focusPrompt = ""
        self.requestsPrompt = ""
        self.guideNotesPrompt = ""
        self.sortOrder = 0
        self.isActive = false
        self.isBuiltIn = false
    }
}
