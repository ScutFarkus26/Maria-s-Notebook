import Foundation
import CoreData

@objc(CDStudent)
nonisolated public class CDStudent: NSManagedObject {
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
    @NSManaged public var previousLevelRaw: String?
    @NSManaged public var dateLastPromoted: Date?
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
        self.previousLevelRaw = nil
        self.dateLastPromoted = nil
        self.modifiedAt = Date()
    }
}

// MARK: - Computed Properties

nonisolated extension CDStudent {
    var level: Level {
        get { Level(rawValue: levelRaw) ?? .lower }
        set { levelRaw = newValue.rawValue }
    }

    var enrollmentStatus: EnrollmentStatus {
        get { EnrollmentStatus(rawValue: enrollmentStatusRaw) ?? .enrolled }
        set { enrollmentStatusRaw = newValue.rawValue }
    }

    var isWithdrawn: Bool { enrollmentStatus == .withdrawn }
    var isTransferred: Bool { enrollmentStatus == .transferred }
    var isEnrolled: Bool { enrollmentStatus == .enrolled }

    /// True for any student no longer on the active roster (withdrawn or transferred).
    var isDeparted: Bool { !isEnrolled }

    /// `dateWithdrawn` doubles as the departure date for transferred students.
    var dateDeparted: Date? {
        get { dateWithdrawn }
        set { dateWithdrawn = newValue }
    }

    /// The level held before the most recent promotion, if one was recorded.
    var previousLevel: Level? {
        get { previousLevelRaw.flatMap(Level.init(rawValue:)) }
        set { previousLevelRaw = newValue?.rawValue }
    }

    var fullName: String {
        "\(firstName) \(lastName)"
    }

    /// Uppercased initials for avatar display (e.g. "JD" for John Doe).
    var initials: String {
        let parts = fullName.split(separator: " ")
        if parts.count >= 2 {
            let first = parts.first?.first.map(String.init) ?? ""
            let last = parts.last?.first.map(String.init) ?? ""
            return (first + last).uppercased()
        } else if let first = fullName.first {
            return String(first).uppercased()
        } else {
            return "?"
        }
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
