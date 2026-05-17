import Foundation
import CoreData

@objc(CDInitiative)
public class CDInitiative: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var title: String
    @NSManaged public var notes: String
    @NSManaged public var deadline: Date?
    @NSManaged public var completedAt: Date?
    @NSManaged public var area: String?
    @NSManaged public var colorRaw: String?
    @NSManaged public var symbol: String?
    @NSManaged public var orderIndex: Int64
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?
    @NSManaged public var notificationIDs: NSObject?
    @NSManaged public var leadTimeDaysRaw: NSObject?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "Initiative", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.title = ""
        self.notes = ""
        self.deadline = nil
        self.completedAt = nil
        self.area = nil
        self.colorRaw = nil
        self.symbol = nil
        self.orderIndex = 0
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.notificationIDs = nil
        self.leadTimeDaysRaw = nil
    }
}

// MARK: - Typed accessors for Transformable arrays

extension CDInitiative {
    var notificationIDsArray: [String] {
        get { (notificationIDs as? [String]) ?? [] }
        set { notificationIDs = newValue.isEmpty ? nil : (newValue as NSArray) }
    }

    var leadTimeDaysArray: [Int] {
        get { (leadTimeDaysRaw as? [Int]) ?? [] }
        set { leadTimeDaysRaw = newValue.isEmpty ? nil : (newValue as NSArray) }
    }
}

// MARK: - Status helpers

extension CDInitiative {
    var isCompleted: Bool { completedAt != nil }

    /// nil deadline → never overdue.
    var isOverdue: Bool {
        guard !isCompleted, let deadline else { return false }
        return deadline < Calendar.current.startOfDay(for: Date())
    }

    /// Whole days from today (start-of-day) to the deadline. Negative if past.
    /// Returns nil if there is no deadline.
    var daysUntilDeadline: Int? {
        guard let deadline else { return nil }
        let start = Calendar.current.startOfDay(for: Date())
        let target = Calendar.current.startOfDay(for: deadline)
        return Calendar.current.dateComponents([.day], from: start, to: target).day
    }
}
