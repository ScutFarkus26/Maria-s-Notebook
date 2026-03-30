import Foundation
import CoreData

/// Represents a collaborative practice session where one or more students work together
/// on their assigned work items.
@objc(PracticeSession)
public class CDPracticeSession: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var date: Date?
    @NSManaged public var duration: Double  // TimeInterval stored as Double; 0 means unset
    @NSManaged public var studentIDs: NSObject?  // Transformable [String]
    @NSManaged public var workItemIDs: NSObject?  // Transformable [String]
    @NSManaged public var workStepID: String?
    @NSManaged public var sharedNotes: String
    @NSManaged public var location: String?
    @NSManaged public var practiceQuality: Int64  // 0 means unset
    @NSManaged public var independenceLevel: Int64  // 0 means unset
    @NSManaged public var askedForHelp: Bool
    @NSManaged public var helpedPeer: Bool
    @NSManaged public var struggledWithConcept: Bool
    @NSManaged public var madeBreakthrough: Bool
    @NSManaged public var needsReteaching: Bool
    @NSManaged public var readyForCheckIn: Bool
    @NSManaged public var readyForAssessment: Bool
    @NSManaged public var checkInScheduledFor: Date?
    @NSManaged public var followUpActions: String
    @NSManaged public var materialsUsed: String

    // MARK: - Relationships
    @NSManaged public var notes: NSSet?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "PracticeSession", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.createdAt = Date()
        self.date = Date()
        self.duration = 0
        self.studentIDs = [] as NSArray
        self.workItemIDs = [] as NSArray
        self.workStepID = nil
        self.sharedNotes = ""
        self.location = nil
        self.practiceQuality = 0
        self.independenceLevel = 0
        self.askedForHelp = false
        self.helpedPeer = false
        self.struggledWithConcept = false
        self.madeBreakthrough = false
        self.needsReteaching = false
        self.readyForCheckIn = false
        self.readyForAssessment = false
        self.checkInScheduledFor = nil
        self.followUpActions = ""
        self.materialsUsed = ""
    }
}

// MARK: - Computed Properties

extension CDPracticeSession {
    /// Access studentIDs as a Swift [String] array
    var studentIDsArray: [String] {
        get { (studentIDs as? [String]) ?? [] }
        set { studentIDs = newValue as NSArray }
    }

    /// Access workItemIDs as a Swift [String] array
    var workItemIDsArray: [String] {
        get { (workItemIDs as? [String]) ?? [] }
        set { workItemIDs = newValue as NSArray }
    }

    /// Duration as optional TimeInterval (nil if 0)
    var durationInterval: TimeInterval? {
        get { duration > 0 ? duration : nil }
        set { duration = newValue ?? 0 }
    }

    /// Practice quality as optional Int (nil if 0)
    var practiceQualityValue: Int? {
        get { practiceQuality > 0 ? Int(practiceQuality) : nil }
        set { practiceQuality = Int64(newValue ?? 0) }
    }

    /// Independence level as optional Int (nil if 0)
    var independenceLevelValue: Int? {
        get { independenceLevel > 0 ? Int(independenceLevel) : nil }
        set { independenceLevel = Int64(newValue ?? 0) }
    }

    /// Returns true if this is a group practice session (2+ students)
    var isGroupSession: Bool {
        studentIDsArray.count > 1
    }

    /// Returns true if this is a solo practice session (1 student)
    var isSoloSession: Bool {
        studentIDsArray.count == 1
    }

    /// Number of students who participated
    var participantCount: Int {
        studentIDsArray.count
    }

    /// Number of work items practiced
    var workItemCount: Int {
        workItemIDsArray.count
    }

    /// Formatted duration string (e.g., "30 min", "1.5 hrs")
    var durationFormatted: String? {
        guard duration > 0 else { return nil }
        let minutes = Int(duration / 60)
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = Double(minutes) / 60.0
            return String(format: "%.1f hrs", hours)
        }
    }

    /// Label for practice quality level
    var practiceQualityLabel: String? {
        guard practiceQuality > 0 else { return nil }
        switch Int(practiceQuality) {
        case 1: return "Distracted"
        case 2: return "Minimal"
        case 3: return "Adequate"
        case 4: return "Good"
        case 5: return "Excellent"
        default: return nil
        }
    }

    /// Label for independence level
    var independenceLevelLabel: String? {
        guard independenceLevel > 0 else { return nil }
        switch Int(independenceLevel) {
        case 1: return "Needs Constant Help"
        case 2: return "Frequent Guidance"
        case 3: return "Some Support"
        case 4: return "Mostly Independent"
        case 5: return "Fully Independent"
        default: return nil
        }
    }

    /// Returns active behavior flags as readable strings
    var activeBehaviors: [String] {
        var behaviors: [String] = []
        if askedForHelp { behaviors.append("Asked for help") }
        if helpedPeer { behaviors.append("Helped peer") }
        if struggledWithConcept { behaviors.append("Struggled") }
        if madeBreakthrough { behaviors.append("Breakthrough!") }
        if needsReteaching { behaviors.append("Needs reteaching") }
        if readyForCheckIn { behaviors.append("Ready for check-in") }
        if readyForAssessment { behaviors.append("Ready for assessment") }
        return behaviors
    }

    /// Returns true if any action flags are set
    var hasActionFlags: Bool {
        needsReteaching || readyForCheckIn || readyForAssessment
    }

    /// Returns true if there are scheduled next steps
    var hasNextSteps: Bool {
        checkInScheduledFor != nil || !followUpActions.isEmpty
    }

    // MARK: - Helper Methods

    /// Checks if a specific student participated in this session
    func includes(studentID: UUID) -> Bool {
        studentIDsArray.contains(studentID.uuidString)
    }

    /// Checks if a specific work item was practiced in this session
    func includes(workItemID: UUID) -> Bool {
        workItemIDsArray.contains(workItemID.uuidString)
    }

    /// Returns student UUIDs from the stored string IDs
    var studentUUIDs: [UUID] {
        studentIDsArray.compactMap { UUID(uuidString: $0) }
    }

    /// Returns work item UUIDs from the stored string IDs
    var workItemUUIDs: [UUID] {
        workItemIDsArray.compactMap { UUID(uuidString: $0) }
    }

    /// Returns the work step UUID if set
    var workStepUUID: UUID? {
        workStepID.flatMap { UUID(uuidString: $0) }
    }

    /// Adds a student to the practice session if not already present
    func addStudent(_ studentID: UUID) {
        let idString = studentID.uuidString
        var ids = studentIDsArray
        if !ids.contains(idString) {
            ids.append(idString)
            studentIDsArray = ids
        }
    }

    /// Adds a work item to the practice session if not already present
    func addWorkItem(_ workItemID: UUID) {
        let idString = workItemID.uuidString
        var ids = workItemIDsArray
        if !ids.contains(idString) {
            ids.append(idString)
            workItemIDsArray = ids
        }
    }

    /// Removes a student from the practice session
    func removeStudent(_ studentID: UUID) {
        let idString = studentID.uuidString
        var ids = studentIDsArray
        ids.removeAll { $0 == idString }
        studentIDsArray = ids
    }

    /// Removes a work item from the practice session
    func removeWorkItem(_ workItemID: UUID) {
        let idString = workItemID.uuidString
        var ids = workItemIDsArray
        ids.removeAll { $0 == idString }
        workItemIDsArray = ids
    }
}

// MARK: - Generated Accessors for To-Many Relationships

extension CDPracticeSession {
    @objc(addNotesObject:)
    @NSManaged public func addToNotes(_ value: CDNote)

    @objc(removeNotesObject:)
    @NSManaged public func removeFromNotes(_ value: CDNote)

    @objc(addNotes:)
    @NSManaged public func addToNotes(_ values: NSSet)

    @objc(removeNotes:)
    @NSManaged public func removeFromNotes(_ values: NSSet)
}
