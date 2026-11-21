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
    /// The child's `student_id` on the school's ParentLocker site, stored once
    /// matched by name so later sends go by ID and survive a rename (schema
    /// 18). Only the guide's devices write it.
    @NSManaged public var parentLockerID: String?
    /// Born after sunset: a Hebrew date begins at sunset, so the child's
    /// Hebrew birthday is the next day's (schema 21). The Hebrew date itself
    /// is worked out wherever it's shown, never stored. A record from before
    /// schema 21 holds no value, which reads as false.
    @NSManaged public var bornAfterSunset: Bool
    @NSManaged public var modifiedAt: Date?

    // Schema 9 removed the `trackEnrollments` relationship: it pulled a
    // child's tracks, steps and lessons into the classroom share. Schema 23
    // retired the track entities themselves.

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "Student", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.firstName = ""
        self.lastName = ""
        self.nickname = nil
        // No birthday until one is known: today's date read as a newborn.
        self.birthday = nil
        self.levelRaw = Level.lower.rawValue
        self.nextLessons = [] as NSArray
        self.manualOrder = 0
        self.dateStarted = nil
        self.enrollmentStatusRaw = EnrollmentStatus.enrolled.rawValue
        self.dateWithdrawn = nil
        self.previousLevelRaw = nil
        self.dateLastPromoted = nil
        self.bornAfterSunset = false
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

    /// The shortened classroom form of the name: "FirstName L" (e.g. "Maya S"),
    /// or just the first name when there is no last name.
    ///
    /// The rule lives here rather than in `StudentFormatter` because the Daybook
    /// Assistant target compiles this file without the formatter.
    var shortName: String {
        Self.shortName(firstName: firstName, lastName: lastName)
    }

    /// Same rule as `shortName` for callers holding raw name fields (log rows, DTOs).
    static func shortName(firstName: String, lastName: String) -> String {
        let first = firstName.trimmed()
        let last = lastName.trimmed()
        guard !first.isEmpty else { return last }
        guard let initial = last.first else { return first }
        return "\(first) \(String(initial).uppercased())"
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

// MARK: - In class

// "Was she in the class then?" has one answer (domain logic review
// 2026-11-20, R7). A departed child's `dateWithdrawn` is her last day in
// class, inclusive: recorded on Monday that Maya leaves Friday, she is in
// class through Friday. A departed child with no date is out. A start date
// after the day keeps her out of that day.
//
// `isEnrolled` stays the stored status alone, for the few places that mean
// the status itself (the departure prompt, "not started" against "left").
// The attendance roll, the history lenses, the classroom share, the parent
// reports' queue and Claude's work writes all read this rule, and today's
// lists (`filterEnrolled`, `enrolledPredicate`) read `hasLeft(by:)`, its
// departure half: a child whose start date is still to come is on them, as
// she always was. This file is compiled by the Daybook Assistant too.

nonisolated extension CDStudent {

    /// Whether a child with these dates was in the class at some point in
    /// `[start, end)`: started before `end` (or no start date), and still
    /// enrolled or departed on or after `start`'s day.
    static func isInClass(
        status: EnrollmentStatus, started: Date?, lastDay: Date?,
        from start: Date, until end: Date, calendar: Calendar = AppCalendar.shared
    ) -> Bool {
        if let started, started >= end { return false }
        return !hasLeft(status: status, lastDay: lastDay, by: start, calendar: calendar)
    }

    /// Whether a child with this status and last day had left the class by
    /// `day`: departed, with no last day or one before `day`'s.
    static func hasLeft(
        status: EnrollmentStatus, lastDay: Date?, by day: Date, calendar: Calendar = AppCalendar.shared
    ) -> Bool {
        switch status {
        case .enrolled:
            return false
        case .withdrawn, .transferred:
            guard let lastDay else { return true }
            return calendar.startOfDay(for: lastDay) < calendar.startOfDay(for: day)
        }
    }

    /// Whether she is in the class on `day`.
    func isInClass(on day: Date, calendar: Calendar = AppCalendar.shared) -> Bool {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return isInClass(from: start, until: end, calendar: calendar)
    }

    /// Whether she was in the class at some point in `[start, end)`.
    func isInClass(from start: Date, until end: Date, calendar: Calendar = AppCalendar.shared) -> Bool {
        Self.isInClass(
            status: enrollmentStatus, started: dateStarted, lastDay: dateWithdrawn,
            from: start, until: end, calendar: calendar
        )
    }

    /// Whether she had left the class by `day`. Today's lists keep a child
    /// until this is true.
    func hasLeft(by day: Date = Date(), calendar: Calendar = AppCalendar.shared) -> Bool {
        Self.hasLeft(status: enrollmentStatus, lastDay: dateWithdrawn, by: day, calendar: calendar)
    }

    /// `hasLeft(by:)` as a fetch predicate: the children who hadn't left by
    /// `day`.
    static func notLeftPredicate(by day: Date = Date(), calendar: Calendar = AppCalendar.shared) -> NSPredicate {
        NSPredicate(
            format: "enrollmentStatusRaw == %@ OR (enrollmentStatusRaw != %@ AND dateWithdrawn >= %@)",
            EnrollmentStatus.enrolled.rawValue,
            EnrollmentStatus.enrolled.rawValue,
            calendar.startOfDay(for: day) as NSDate
        )
    }
}
