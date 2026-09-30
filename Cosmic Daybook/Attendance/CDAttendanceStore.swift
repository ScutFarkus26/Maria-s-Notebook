import Foundation
import CoreData

/// Core Data service layer for fetching/upserting and updating attendance records.
///
/// Every mutation flows through here (grid, repository, Siri intent, companion app),
/// which makes this the chokepoint for two cross-device concerns:
/// - **Attribution**: each change stamps `recordedBy` (the device's `ClassroomRole`)
///   and `modifiedAt`, which the dedup comparator uses for last-writer-wins.
/// - **Permissions**: mutations are gated by `ClassroomPermissions.canWrite` — a
///   no-op for lead guides, real enforcement for assistants — and by the day's
///   lock (`AttendanceDayLocks`), which holds for everyone until the lead guide
///   unlocks the day.
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

    /// Whether `date` is locked. A locked day takes no edits from anyone.
    func isLocked(_ date: Date) -> Bool {
        AttendanceDayLocks.isLocked(date, in: context)
    }

    /// This role may write attendance and `date` isn't locked. Screens ask
    /// this rather than repeating the rule.
    func canWrite(on date: Date?) -> Bool {
        canWrite && !isLocked(date ?? Date())
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

    /// Sets the status and dates it. `markedAt` is when the status was set,
    /// except that Left Early keeps the arrival time from a present or tardy
    /// mark and puts the time the child left in `leftAt`. Unmarked has
    /// neither.
    ///
    /// Only a mark made on the day it's for gets a time: correcting Monday
    /// on Wednesday would otherwise record Wednesday's clock as Monday's
    /// arrival, and a vacation marked ahead has no time of day at all.
    private func mark(_ record: CDAttendanceRecord, as status: AttendanceStatus, at now: Date) {
        let previous = record.status
        record.status = status
        let isToday = record.date.map { calendar.isDate($0, inSameDayAs: now) } ?? false
        let time = isToday ? now : nil
        switch status {
        case .unmarked:
            record.markedAt = nil
            record.leftAt = nil
        case .leftEarly:
            if previous != .present && previous != .tardy { record.markedAt = nil }
            record.leftAt = time
        case .present, .absent, .tardy:
            record.markedAt = time
            record.leftAt = nil
        }
        stamp(record)
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
        guard canWrite(on: date) else { return nil }
        let key = student.id?.uuidString ?? ""
        guard !key.isEmpty else { return nil }
        let day = date.normalizedDay(using: calendar)
        let existing = try fetchRecords(for: day).filter { $0.studentID == key }
        if let winner = existing.deduplicatedPerStudentDay().first {
            return winner
        }
        return makeRecord(studentKey: key, day: day)
    }

    /// `ensureRecord` for a whole class at once: the day's records are
    /// fetched once instead of once per child (and the lock checked once, by
    /// the caller, instead of per child). Pending inserts are part of the
    /// fetch, and a child named twice gets the same record twice, as
    /// `ensureRecord` would give. Existing duplicates collapse to the winner.
    private func ensureRecords(for students: [CDStudent], on date: Date) throws -> [CDAttendanceRecord] {
        let day = date.normalizedDay(using: calendar)
        var byStudent: [String: CDAttendanceRecord] = [:]
        for record in try fetchRecords(for: day).deduplicatedPerStudentDay() {
            byStudent[record.studentID] = record
        }
        var records: [CDAttendanceRecord] = []
        for student in students {
            let key = student.id?.uuidString ?? ""
            guard !key.isEmpty else { continue }
            let record = byStudent[key] ?? makeRecord(studentKey: key, day: day)
            byStudent[key] = record
            records.append(record)
        }
        return records
    }

    /// A new, unmarked record for (student, day), in the store this role's
    /// records belong in.
    private func makeRecord(studentKey: String, day: Date) -> CDAttendanceRecord {
        let rec = CDAttendanceRecord(context: context)
        if let store = destinationStore {
            context.assign(rec, to: store)
        }
        rec.studentID = studentKey
        rec.date = day
        rec.status = .unmarked
        rec.absenceReason = .none
        stamp(rec)
        return rec
    }

    /// Update a record's status and return whether it changed.
    @discardableResult
    func updateStatus(_ record: CDAttendanceRecord, to newStatus: AttendanceStatus) -> Bool {
        guard canWrite(on: record.date) else { return false }
        guard record.status != newStatus else { return false }
        mark(record, as: newStatus, at: Date())
        return true
    }

    /// Update a record's note and return whether it changed. The note is on
    /// the shared record, so the guide and an assistant both see it.
    @discardableResult
    func updateNote(_ record: CDAttendanceRecord, to newNote: String?) -> Bool {
        guard canWrite(on: record.date) else { return false }
        let trimmed = newNote?.trimmed()
        let newVal = (trimmed?.isEmpty == true) ? nil : trimmed
        guard record.note != newVal else { return false }
        record.note = newVal
        stamp(record)
        return true
    }

    /// Update a record's absence reason and return whether it changed.
    @discardableResult
    func updateAbsenceReason(_ record: CDAttendanceRecord, to newReason: AbsenceReason) -> Bool {
        guard canWrite(on: record.date) else { return false }
        guard record.status == .absent else { return false }
        let old = record.absenceReason
        record.absenceReason = newReason
        guard old != newReason else { return false }
        stamp(record)
        return true
    }

    /// Puts an absence's reason back exactly as it was, stored value and all
    /// (Close Arrival's automatic marker included), for Siri's Undo of a
    /// reason-only change. Returns whether it changed.
    @discardableResult
    func restoreAbsenceReason(_ record: CDAttendanceRecord, toRaw raw: String) -> Bool {
        guard canWrite(on: record.date), record.status == .absent, record.absenceReasonRaw != raw else {
            return false
        }
        record.absenceReasonRaw = raw
        stamp(record)
        return true
    }

    /// Whether arrival has closed on `date` somewhere: a record that day
    /// carries Close Arrival's automatic absence. The Late phase itself is
    /// only on the iPhone that closed it; this is what everyone else sees.
    func arrivalClosed(on date: Date) throws -> Bool {
        try loadRecords(for: date).contains(where: AttendanceDeduplication.isAutomaticAbsence)
    }

    /// Convenience: Mark all students present for the date, creating missing records.
    /// Callers save immediately afterwards — this is a deliberate bulk action, not a
    /// screen-open side effect.
    @discardableResult
    func markAllPresent(for date: Date, students: [CDStudent]) throws -> [CDAttendanceRecord] {
        guard canWrite(on: date) else { return [] }
        let now = Date()
        let records = try ensureRecords(for: students, on: date)
        for rec in records where rec.status != .present {
            mark(rec, as: .present, at: now)
        }
        return records
    }

    /// Marks every student still unmarked on `date` absent, creating records
    /// for those without one: the moment the morning's arrival window closes.
    /// Anyone already marked keeps their mark. Returns only the records it
    /// changed, so the caller can undo exactly those. Callers save afterwards.
    @discardableResult
    func markUnmarkedAbsent(for date: Date, students: [CDStudent]) throws -> [CDAttendanceRecord] {
        guard canWrite(on: date) else { return [] }
        let now = Date()
        var changed: [CDAttendanceRecord] = []
        // A status this build doesn't know (a newer build's) reads as
        // unmarked but isn't: leave it rather than overwrite it with absent.
        for rec in try ensureRecords(for: students, on: date)
        where rec.status == .unmarked && (rec.statusRaw.isEmpty || AttendanceStatus(rawValue: rec.statusRaw) != nil) {
            mark(rec, as: .absent, at: now)
            // Loses a duplicate to any real mark (`AttendanceDeduplication.wins`).
            rec.absenceReasonRaw = AttendanceDeduplication.automaticAbsenceRaw
            changed.append(rec)
        }
        return changed
    }

    #if !ASSISTANT_APP

    /// Deletes a record, unless this role can't write or its day is locked.
    /// Returns whether it did. The caller saves.
    @discardableResult
    func delete(_ record: CDAttendanceRecord) -> Bool {
        guard canWrite(on: record.date) else { return false }
        context.delete(record)
        return true
    }

    /// Resets the date's existing records to unmarked and clears their reasons
    /// and notes. Students without a record are left alone — no record already
    /// reads as unmarked. Returns what each record it cleared held before, for
    /// `restore(_:)`. Callers save immediately afterwards.
    @discardableResult
    func resetDay(for date: Date, students: [CDStudent]) throws -> [AttendanceRecordSnapshot] {
        guard canWrite(on: date) else { return [] }
        let studentIDs = Set(students.compactMap { $0.id?.uuidString })
        let records = try loadRecords(for: date).filter {
            studentIDs.contains($0.studentID) && !AttendanceRecordSnapshot.isBlank($0)
        }
        // An unsaved record's id is temporary and won't find it after the
        // save that follows; the snapshot needs the one that lasts.
        try context.obtainPermanentIDs(for: records.filter(\.objectID.isTemporaryID))
        var cleared: [AttendanceRecordSnapshot] = []
        for rec in records {
            cleared.append(AttendanceRecordSnapshot(rec))
            rec.absenceReason = .none
            rec.note = nil
            mark(rec, as: .unmarked, at: Date())
        }
        return cleared
    }

    /// Undoes a reset: each record gets back what it held, unless it has been
    /// marked (or given a note) again since. Nothing on a locked day. Returns
    /// the records put back. Callers save afterwards.
    @discardableResult
    func restore(_ snapshots: [AttendanceRecordSnapshot]) -> [CDAttendanceRecord] {
        var restored: [CDAttendanceRecord] = []
        for snapshot in snapshots {
            guard let rec = try? context.existingObject(with: snapshot.objectID) as? CDAttendanceRecord,
                  !rec.isDeleted,
                  canWrite(on: rec.date),
                  AttendanceRecordSnapshot.isBlank(rec) else { continue }
            snapshot.apply(to: rec)
            restored.append(rec)
        }
        return restored
    }

    #endif
}
