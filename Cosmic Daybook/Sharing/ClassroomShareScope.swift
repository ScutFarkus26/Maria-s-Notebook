import CoreData
import Foundation

/// Which classroom records belong in the share: this school year only.
///
/// - A **student** belongs while she is enrolled, and for the rest of the school year she
///   leaves in — departed on or after its first day (`dateWithdrawn`), or with any attendance
///   from this year, which covers a missing or placeholder departure date. So a child who
///   leaves mid-year drops off today's roll but still shows, with her marks, on the days she
///   was here.
/// - An **attendance record** belongs when it is dated on or after the school year's first
///   day and its student belongs.
/// - Everything else the share holds (days off, extra school days, locked days, the
///   front-desk email, Restock's staples and needs) always belongs.
///
/// The first day is the school-year start (`YearPlanStaleness.currentYearStart`, the synced
/// setting). Records outside the scope stay in the notebook; they just aren't shared. Every
/// path that puts records into the share filters through this (Set Up Classroom Sharing,
/// "Add Them to the Share", `SharedStoreOrphanGuard`), and `ClassroomShareRelease` takes out
/// what falls outside it when a school year ends.
nonisolated struct ClassroomShareScope: Sendable, Equatable {
    /// Bumped whenever the scope's rules or the safety net around releasing records change,
    /// and logged at launch, so a device's build can be checked before a release (the Mac's
    /// release refuses to reason about devices it can't see; this is how a person can).
    static let version = 1

    /// Start of the first day of the school year the share holds.
    let cutoff: Date

    /// The cutoff is only the September 1 fallback: the class's school-year start
    /// hasn't reached this device yet (`YearPlanStaleness.hasConfiguredStart`; a
    /// new device before iCloud key-value storage arrives). Marks it calls last
    /// year's may be this year's first days (in 2026 the class began August 25),
    /// so the classroom share's waiting list keeps them instead of dropping them.
    let isProvisional: Bool

    init(cutoff: Date, isProvisional: Bool = false) {
        self.cutoff = AppCalendar.startOfDay(cutoff)
        self.isProvisional = isProvisional
    }

    /// This school year, as this device knows it.
    init() {
        self.init(
            cutoff: YearPlanStaleness.currentYearStart(),
            isProvisional: !YearPlanStaleness.hasConfiguredStart
        )
    }

    /// Zone-name prefix `NSPersistentCloudKitContainer` gives the zones that back a `CKShare`
    /// (`com.apple.coredata.cloudkit.share.<UUID>`).
    static let shareZonePrefix = "com.apple.coredata.cloudkit.share."

    static func isShareZone(_ zoneName: String?) -> Bool {
        zoneName?.hasPrefix(shareZonePrefix) == true
    }

    /// The share types whose every record belongs, whatever its date.
    static let alwaysSharedEntityNames = CoreDataStack.sharedEntityNames.subtracting(["Student", "AttendanceRecord"])

    // MARK: - The rules

    func studentBelongs(status: CDStudent.EnrollmentStatus, dateWithdrawn: Date?, hasAttendanceThisYear: Bool) -> Bool {
        if status == .enrolled || hasAttendanceThisYear { return true }
        guard let dateWithdrawn else { return false }
        return AppCalendar.startOfDay(dateWithdrawn) >= cutoff
    }

    /// `belongingStudentIDs` must be normalized with `normalizedID`.
    func attendanceBelongs(date: Date?, studentID: String, belongingStudentIDs: Set<String>) -> Bool {
        guard isThisYear(date) else { return false }
        return belongingStudentIDs.contains(Self.normalizedID(studentID))
    }

    func isThisYear(_ date: Date?) -> Bool {
        guard let date else { return false }
        return AppCalendar.startOfDay(date) >= cutoff
    }

    /// Student ids compare case-insensitively: a `studentID` string written by hand or by an
    /// older path may not match `UUID.uuidString`'s upper case (`StudentDeletion` matches
    /// `==[c]` for the same reason).
    static func normalizedID(_ id: String) -> String {
        id.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    // MARK: - Reading the store

    /// The normalized ids of every student in `store` who belongs. Reads columns only.
    func belongingStudentIDs(in context: NSManagedObjectContext, store: NSPersistentStore?) -> Set<String> {
        let marked = studentIDsWithAttendanceThisYear(in: context, store: store)
        let request = NSFetchRequest<NSDictionary>(entityName: "Student")
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["id", "enrollmentStatusRaw", "dateWithdrawn"]
        if let store { request.affectedStores = [store] }
        let rows = (try? context.fetch(request)) ?? []
        var ids = Set<String>()
        for row in rows {
            guard let id = (row["id"] as? UUID)?.uuidString else { continue }
            let key = Self.normalizedID(id)
            let raw = row["enrollmentStatusRaw"] as? String ?? ""
            let status = CDStudent.EnrollmentStatus(rawValue: raw) ?? .enrolled
            let withdrawn = row["dateWithdrawn"] as? Date
            if studentBelongs(status: status, dateWithdrawn: withdrawn, hasAttendanceThisYear: marked.contains(key)) {
                ids.insert(key)
            }
        }
        return ids
    }

    /// Normalized student ids with any attendance record dated this school year.
    func studentIDsWithAttendanceThisYear(
        in context: NSManagedObjectContext, store: NSPersistentStore?
    ) -> Set<String> {
        let request = NSFetchRequest<NSDictionary>(entityName: "AttendanceRecord")
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["studentID"]
        request.returnsDistinctResults = true
        request.predicate = NSPredicate(format: "date >= %@", cutoff as NSDate)
        if let store { request.affectedStores = [store] }
        let rows = (try? context.fetch(request)) ?? []
        return Set(rows.compactMap { ($0["studentID"] as? String).map(Self.normalizedID) })
    }

    /// Of `ids`, the ones this scope keeps (all of them for the always-shared types). One
    /// read per entity; ids that no longer resolve are dropped.
    func filter(_ ids: [NSManagedObjectID], in context: NSManagedObjectContext) -> [NSManagedObjectID] {
        guard !ids.isEmpty else { return [] }
        let needsStudents = ids.contains { ["Student", "AttendanceRecord"].contains($0.entity.name ?? "") }
        let store = ids.first?.persistentStore
        let belonging = needsStudents ? belongingStudentIDs(in: context, store: store) : []
        return ids.filter { id in
            switch id.entity.name {
            case "Student":
                guard let student = try? context.existingObject(with: id) as? CDStudent,
                      let sid = student.id?.uuidString else { return false }
                return belonging.contains(Self.normalizedID(sid))
            case "AttendanceRecord":
                guard let record = try? context.existingObject(with: id) as? CDAttendanceRecord else { return false }
                return attendanceBelongs(date: record.date, studentID: record.studentID, belongingStudentIDs: belonging)
            default:
                return true
            }
        }
    }

    /// Fetch predicates that select this scope's rows of `entityName`, given the belonging
    /// ids. Nil for the always-shared types (every row).
    func predicate(for entityName: String, belongingStudentIDs: Set<String>) -> NSPredicate? {
        switch entityName {
        case "Student":
            return NSPredicate(format: "id IN %@", belongingStudentIDs.compactMap(UUID.init(uuidString:)))
        case "AttendanceRecord":
            // As `normalizedID` compares: any case, any whitespace around the id. `IN` is
            // case-sensitive (the SQLite store ignores `IN[c]`), so a mixed-case `studentID`
            // the release counts as this year's read as last year's here, and Settings showed
            // a count with nothing to remove. `MATCHES` runs in the SQLite store too.
            guard !belongingStudentIDs.isEmpty else {
                return NSPredicate(format: "date >= %@ AND studentID IN %@", cutoff as NSDate, [String]())
            }
            let ids = belongingStudentIDs.sorted().map(NSRegularExpression.escapedPattern(for:))
            let pattern = "(?i)\\s*(?:" + ids.joined(separator: "|") + ")\\s*"
            return NSPredicate(format: "date >= %@ AND studentID MATCHES %@", cutoff as NSDate, pattern)
        default:
            return nil
        }
    }

    // MARK: - The first day, checked

    /// When attendance was taken in the two weeks before the cutoff, the school-year start is
    /// set later than the first day school actually met: releasing now would take this year's
    /// first marks out of the share. Returns the earliest such day, or nil when there is none.
    func attendanceJustBeforeCutoff(in context: NSManagedObjectContext, store: NSPersistentStore?) -> Date? {
        guard let windowStart = AppCalendar.shared.date(byAdding: .day, value: -14, to: cutoff) else { return nil }
        let request = NSFetchRequest<CDAttendanceRecord>(entityName: "AttendanceRecord")
        request.predicate = NSPredicate(format: "date >= %@ AND date < %@", windowStart as NSDate, cutoff as NSDate)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        request.fetchLimit = 1
        if let store { request.affectedStores = [store] }
        return (try? context.fetch(request))?.first?.date
    }
}
