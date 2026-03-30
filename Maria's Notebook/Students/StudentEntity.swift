import Foundation
import CoreData

@objc(Student)
public class CDStudent: NSManagedObject {
    // MARK: - Type Aliases (enums defined in SwiftData models)
    typealias EnrollmentStatus = Student.EnrollmentStatus
    typealias Level = Student.Level

    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var firstName: String
    @NSManaged public var lastName: String
    @NSManaged public var nickname: String?
    @NSManaged public var birthday: Date?
    @NSManaged public var levelRaw: String
    @NSManaged public var nextLessons: NSObject?  // Transformable [String]
    @NSManaged public var manualOrder: Int64
    @NSManaged public var dateStarted: Date?
    @NSManaged public var enrollmentStatusRaw: String
    @NSManaged public var dateWithdrawn: Date?
    @NSManaged public var modifiedAt: Date?

    // MARK: - Relationships
    @NSManaged public var documents: NSSet?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "Student", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.firstName = ""
        self.lastName = ""
        self.nickname = nil
        self.birthday = Date()
        self.levelRaw = Level.lower.rawValue
        self.nextLessons = [] as NSArray
        self.manualOrder = 0
        self.dateStarted = nil
        self.enrollmentStatusRaw = EnrollmentStatus.enrolled.rawValue
        self.dateWithdrawn = nil
        self.modifiedAt = Date()
    }
}

// MARK: - Enums

extension CDStudent {

}

// MARK: - Computed Properties

extension CDStudent {
    var level: Level {
        get { Level(rawValue: levelRaw) ?? .lower }
        set { levelRaw = newValue.rawValue }
    }

    var enrollmentStatus: EnrollmentStatus {
        get { EnrollmentStatus(rawValue: enrollmentStatusRaw) ?? .enrolled }
        set { enrollmentStatusRaw = newValue.rawValue }
    }

    var isWithdrawn: Bool { enrollmentStatus == .withdrawn }
    var isEnrolled: Bool { enrollmentStatus == .enrolled }

    var fullName: String {
        "\(firstName) \(lastName)"
    }

    /// Access nextLessons as a Swift [String] array
    var nextLessonsArray: [String] {
        get { (nextLessons as? [String]) ?? [] }
        set { nextLessons = newValue as NSArray }
    }

    /// Convenience computed property to get nextLessons as UUIDs
    var nextLessonUUIDs: [UUID] {
        get { nextLessonsArray.compactMap { UUID(uuidString: $0) } }
        set { nextLessonsArray = newValue.map(\.uuidString) }
    }
}

// MARK: - Generated Accessors for To-Many Relationships

extension CDStudent {
    @objc(addDocumentsObject:)
    @NSManaged public func addToDocuments(_ value: CDDocument)

    @objc(removeDocumentsObject:)
    @NSManaged public func removeFromDocuments(_ value: CDDocument)

    @objc(addDocuments:)
    @NSManaged public func addToDocuments(_ values: NSSet)

    @objc(removeDocuments:)
    @NSManaged public func removeFromDocuments(_ values: NSSet)
}
