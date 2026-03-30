import Foundation
import CoreData

@objc(LessonAssignment)
public class LessonAssignment: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?
    @NSManaged public var stateRaw: String
    @NSManaged public var scheduledFor: Date?
    @NSManaged public var scheduledForDay: Date?
    @NSManaged public var presentedAt: Date?
    @NSManaged public var lessonTitleSnapshot: String?
    @NSManaged public var lessonSubheadingSnapshot: String?
    @NSManaged public var needsPractice: Bool
    @NSManaged public var needsAnotherPresentation: Bool
    @NSManaged public var followUpWork: String
    @NSManaged public var notes: String
    @NSManaged public var manuallyUnblocked: Bool
    @NSManaged public var lessonID: String
    @NSManaged public var _studentIDsData: Data?
    @NSManaged public var studentGroupKeyPersisted: String
    @NSManaged public var trackID: String?
    @NSManaged public var trackStepID: String?
    @NSManaged public var migratedFromStudentLessonID: String?
    @NSManaged public var migratedFromPresentationID: String?

    // MARK: - Relationships
    @NSManaged public var lesson: Lesson?
    @NSManaged public var unifiedNotes: NSSet?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "LessonAssignment", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.stateRaw = LessonAssignmentState.draft.rawValue
        self.scheduledFor = nil
        self.scheduledForDay = Date.distantPast
        self.presentedAt = nil
        self.lessonTitleSnapshot = nil
        self.lessonSubheadingSnapshot = nil
        self.needsPractice = false
        self.needsAnotherPresentation = false
        self.followUpWork = ""
        self.notes = ""
        self.manuallyUnblocked = false
        self.lessonID = ""
        self._studentIDsData = nil
        self.studentGroupKeyPersisted = ""
        self.trackID = nil
        self.trackStepID = nil
        self.migratedFromStudentLessonID = nil
        self.migratedFromPresentationID = nil
    }
}

// MARK: - State Enum

/// Lifecycle states for a presentation.
enum LessonAssignmentState: String, Codable, CaseIterable, Sendable {
    /// Created but not yet scheduled.
    case draft
    /// Has a scheduled date for presentation.
    case scheduled
    /// Has been given to students (historical record).
    case presented
}

// MARK: - Computed Properties

extension LessonAssignment {
    /// Type-safe state accessor.
    var state: LessonAssignmentState {
        get { LessonAssignmentState(rawValue: stateRaw) ?? .draft }
        set { stateRaw = newValue.rawValue }
    }

    /// Student IDs as string array. Uses JSON encoding via CloudKitStringArrayStorage.
    var studentIDs: [String] {
        get { CloudKitStringArrayStorage.decode(from: _studentIDsData) }
        set { _studentIDsData = CloudKitStringArrayStorage.encode(newValue) }
    }

    /// Convenience accessor for lessonID as UUID.
    var lessonIDUUID: UUID? {
        get { UUID(uuidString: lessonID) }
        set { lessonID = newValue?.uuidString ?? "" }
    }

    /// Student IDs as UUIDs.
    var studentUUIDs: [UUID] {
        studentIDs.compactMap { UUID(uuidString: $0) }
    }

    /// Whether this presentation is in the draft state.
    var isDraft: Bool { state == .draft }

    /// Whether this presentation is scheduled.
    var isScheduled: Bool { state == .scheduled || scheduledFor != nil }

    /// Whether this presentation has been given.
    var isPresented: Bool { state == .presented }

    /// Whether this presentation has been given.
    var isGiven: Bool { state == .presented }
}

// MARK: - State Transitions

extension LessonAssignment {
    /// Schedules this presentation for a specific date.
    func schedule(for date: Date, using calendar: Calendar = AppCalendar.shared) {
        self.scheduledFor = date
        self.scheduledForDay = calendar.startOfDay(for: date)
        self.state = .scheduled
        self.modifiedAt = Date()
    }

    /// Removes the scheduled date, returning to draft state.
    func unschedule() {
        self.scheduledFor = nil
        self.scheduledForDay = Date.distantPast
        self.state = .draft
        self.modifiedAt = Date()
    }

    /// Sets `scheduledFor` and updates `scheduledForDay` using the provided calendar.
    func setScheduledFor(_ date: Date?, using calendar: Calendar) {
        if let date {
            schedule(for: date, using: calendar)
        } else {
            unschedule()
        }
    }

    /// Marks this presentation as given.
    func markPresented(at date: Date = Date(), snapshotLesson: Bool = true) {
        self.presentedAt = date
        self.state = .presented
        self.modifiedAt = Date()

        if snapshotLesson, let lesson = self.lesson {
            self.lessonTitleSnapshot = lesson.name
            self.lessonSubheadingSnapshot = lesson.subheading
        }
    }

    /// Creates an immutable snapshot of this presentation for use in value types.
    func snapshot() -> LessonAssignmentSnapshot {
        LessonAssignmentSnapshot(
            id: id ?? UUID(),
            lessonID: lessonIDUUID ?? UUID(),
            studentIDs: studentUUIDs,
            createdAt: createdAt ?? Date(),
            scheduledFor: scheduledFor,
            presentedAt: presentedAt,
            state: state,
            notes: notes,
            needsPractice: needsPractice,
            needsAnotherPresentation: needsAnotherPresentation,
            followUpWork: followUpWork,
            manuallyUnblocked: manuallyUnblocked
        )
    }
}

// MARK: - Snapshot

/// Immutable value-type snapshot of a LessonAssignment for use in SwiftUI and async contexts.
struct LessonAssignmentSnapshot: Identifiable, Sendable {
    let id: UUID
    let lessonID: UUID
    let studentIDs: [UUID]
    let createdAt: Date
    let scheduledFor: Date?
    let presentedAt: Date?
    let state: LessonAssignmentState
    let notes: String
    let needsPractice: Bool
    let needsAnotherPresentation: Bool
    let followUpWork: String
    let manuallyUnblocked: Bool

    var isScheduled: Bool { scheduledFor != nil }
    var isGiven: Bool { state == .presented }
    var isPresented: Bool { state == .presented }
}

// MARK: - Type Aliases

/// Public alias for the unified presentation model.
typealias Presentation = LessonAssignment

/// Public alias for presentation state.
typealias PresentationState = LessonAssignmentState

// MARK: - Generated Accessors for To-Many Relationships

extension LessonAssignment {
    @objc(addUnifiedNotesObject:)
    @NSManaged public func addToUnifiedNotes(_ value: Note)

    @objc(removeUnifiedNotesObject:)
    @NSManaged public func removeFromUnifiedNotes(_ value: Note)

    @objc(addUnifiedNotes:)
    @NSManaged public func addToUnifiedNotes(_ values: NSSet)

    @objc(removeUnifiedNotes:)
    @NSManaged public func removeFromUnifiedNotes(_ values: NSSet)
}

// MARK: - Debug Extensions

#if DEBUG
extension LessonAssignment {
    var debugDescription: String {
        let studentCount = studentIDs.count
        let prefix = lessonID.prefix(8)
        return "Presentation(id=\(id?.uuidString ?? "nil"), state=\(state.rawValue), lessonID=\(prefix)..., students=\(studentCount))"
    }
}
#endif
