import Foundation
import CoreData

/// Core Data service layer for fetching/upserting and updating attendance records.
///
/// Every mutation flows through here (grid, repository, Siri intent, companion app),
/// which makes this the chokepoint for two cross-device concerns:
/// - **Attribution**: each change stamps `recordedBy` (the device's `ClassroomRole`)
///   and `modifiedAt`, which the dedup comparator uses for last-writer-wins.
/// - **Permissions**: mutations are gated by `ClassroomPermissions.canWrite` — a
///   no-op for lead guides, real enforcement for assistants.
///
/// Records are created lazily, one per (student, day), on the first actual mark —
/// never in bulk on screen-open. Two devices opening the same day used to each
/// insert a full roster of unmarked rows, which is exactly the duplicate flood the
/// dedup passes exist to clean up.
struct CDAttendanceStore {
    let context: NSManagedObjectContext
    var calendar: Calendar = .current
    /// The role stamped onto mutations and checked against the permission matrix.
    let role: CDClassroomMembership.ClassroomRole

    init(
        context: NSManagedObjectContext,
        calendar: Calendar = .current,
        role: CDClassroomMembership.ClassroomRole? = nil
    ) {
        self.context = context
        self.calendar = calendar
        self.role = role ?? CDClassroomMembership.currentRole(in: context)
    }

    private var canWrite: Bool {
        ClassroomPermissions.canWrite(entityName: "AttendanceRecord", role: role)
    }

    /// The store a newly created record belongs in.
    ///
    /// Classroom entities live in *both* store configurations, which is what
    /// makes the two-store sharing pattern work — but it also means Core Data
    /// has two candidates for a new record and, absent an explicit assignment,
    /// silently picks the first store added: the private one.
    ///
    /// On the guide's device that happens to be right. On the assistant's it is
    /// exactly wrong: her private store is her own CloudKit database, so her
    /// marks would sync nowhere the guide can see and simply never arrive.
    /// Returns nil in single-store (local/in-memory) setups, where there is
    /// nothing to disambiguate.
    private var destinationStore: NSPersistentStore? {
        guard let coordinator = context.persistentStoreCoordinator,
              coordinator.persistentStores.count > 1 else { return nil }
        let wanted = role == .assistant
            ? CoreDataStack.sharedConfiguration
            : CoreDataStack.privateConfiguration
        return coordinator.persistentStores.first { $0.configurationName == wanted }
    }

    /// Stamps attribution on a record that was just changed.
    private func stamp(_ record: CDAttendanceRecord) {
        record.recordedBy = role.rawValue
        record.recordedByID = ClassroomIdentity.currentUserRecordName
        // Only assistants carry a name: an unlabelled mark is the guide's own,
        // and their own name on their own screen would be noise.
        record.recordedByName = role == .assistant ? ClassroomIdentity.displayName : nil
        record.modifiedAt = Date()
    }

    // Fetch all records for a normalized date.
    private func fetchRecords(for normalizedDate: Date) throws -> [CDAttendanceRecord] {
        let request = CDFetchRequest(CDAttendanceRecord.self)
        request.predicate = NSPredicate(format: "date == %@", normalizedDate as NSDate)
        return try context.fetch(request)
    }

    /// Loads the existing CDAttendanceRecords for the given date (normalized
    /// internally). Creates nothing: the grid renders a student without a record
    /// as unmarked, and ``ensureRecord(for:on:)`` creates one on the first mark.
    func loadRecords(for date: Date) throws -> [CDAttendanceRecord] {
        try fetchRecords(for: date.normalizedDay(using: calendar))
    }

    /// Fetch-or-create the single record for (student, day). Re-fetches before
    /// inserting so a record created moments ago — on this device or another —
    /// is reused instead of duplicated; ties collapse to the dedup winner.
    /// Returns nil when the student has no id or this role cannot write.
    @discardableResult
    func ensureRecord(for student: CDStudent, on date: Date) throws -> CDAttendanceRecord? {
        guard canWrite else { return nil }
        let key = student.id?.uuidString ?? ""
        guard !key.isEmpty else { return nil }
        let day = date.normalizedDay(using: calendar)
        let existing = try fetchRecords(for: day).filter { $0.studentID == key }
        if let winner = existing.deduplicatedPerStudentDay().first {
            return winner
        }
        let rec = CDAttendanceRecord(context: context)
        if let store = destinationStore {
            context.assign(rec, to: store)
        }
        rec.studentID = key
        rec.date = day
        rec.status = .unmarked
        rec.absenceReason = .none
        stamp(rec)
        return rec
    }

    /// Update a record's status and return whether it changed.
    @discardableResult
    func updateStatus(_ record: CDAttendanceRecord, to newStatus: AttendanceStatus) -> Bool {
        guard canWrite else { return false }
        let old = record.status
        record.status = newStatus
        guard old != newStatus else { return false }
        stamp(record)
        return true
    }

    // Note handling is compiled out of the assistant's companion app: its
    // attendance notes stay private to the lead guide, and CDNote's
    // relationships would pull most of the object model into a build that has
    // no use for it.
    #if !ASSISTANT_APP

    /// Update a record's note and return whether it changed.
    @discardableResult
    func updateNote(_ record: CDAttendanceRecord, to newNote: String?) -> Bool {
        guard canWrite else { return false }
        let trimmed = newNote?.trimmed()
        let newVal = (trimmed?.isEmpty == true) ? nil : trimmed
        guard record.setLegacyNoteText(newVal, in: context) else { return false }
        stamp(record)
        return true
    }

    #endif

    /// Update a record's absence reason and return whether it changed.
    @discardableResult
    func updateAbsenceReason(_ record: CDAttendanceRecord, to newReason: AbsenceReason) -> Bool {
        guard canWrite else { return false }
        guard record.status == .absent else { return false }
        let old = record.absenceReason
        record.absenceReason = newReason
        guard old != newReason else { return false }
        stamp(record)
        return true
    }

    /// Convenience: Mark all students present for the date, creating missing records.
    /// Callers save immediately afterwards — this is a deliberate bulk action, not a
    /// screen-open side effect.
    @discardableResult
    func markAllPresent(for date: Date, students: [CDStudent]) throws -> [CDAttendanceRecord] {
        guard canWrite else { return [] }
        var records: [CDAttendanceRecord] = []
        for student in students {
            guard let rec = try ensureRecord(for: student, on: date) else { continue }
            if rec.status != .present {
                rec.status = .present
                stamp(rec)
            }
            records.append(rec)
        }
        return records
    }

    #if !ASSISTANT_APP

    /// Convenience: Reset the date's existing records to unmarked and clear their
    /// notes. Students without a record are left alone — no record already reads
    /// as unmarked. Callers save immediately afterwards.
    @discardableResult
    func resetDay(for date: Date, students: [CDStudent]) throws -> [CDAttendanceRecord] {
        guard canWrite else { return [] }
        let studentIDs = Set(students.compactMap { $0.id?.uuidString })
        var records: [CDAttendanceRecord] = []
        for rec in try loadRecords(for: date) where studentIDs.contains(rec.studentID) {
            let clearedNote = rec.setLegacyNoteText(nil, in: context)
            if rec.status != .unmarked || rec.absenceReason != .none || clearedNote {
                rec.status = .unmarked
                rec.absenceReason = .none
                stamp(rec)
            }
            records.append(rec)
        }
        return records
    }

    #endif
}
