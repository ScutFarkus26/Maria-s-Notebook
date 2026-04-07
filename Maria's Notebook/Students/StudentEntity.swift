import Foundation
import CoreData

@objc(CDStudent)
public class CDStudent: NSManagedObject {
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
    @NSManaged public var trackEnrollments: NSSet?

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

    /// Cross-store inverse: fetches Documents whose studentID matches this student.
    var documents: [CDDocument] {
        guard let id, let ctx = managedObjectContext else { return [] }
        let req = CDFetchRequest(CDDocument.self)
        req.predicate = NSPredicate(format: "studentID == %@", id.uuidString)
        return (try? ctx.fetch(req)) ?? []
    }
}

