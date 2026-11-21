//
//  StudentRepository.swift
//  Cosmic Daybook
//
//  Repository for CDStudent entity CRUD operations.
//

import Foundation
import OSLog
import CoreData

struct StudentRepository: SavingRepository {
    typealias Model = CDStudent

    let context: NSManagedObjectContext
    let saveCoordinator: SaveCoordinator?

    init(context: NSManagedObjectContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch

    /// Fetch a CDStudent by ID
    func fetchStudent(id: UUID) -> CDStudent? { fetch(id: id) }

    /// Every student whose `id` is in `ids`, in store order (a CloudKit duplicate
    /// comes back twice). Throws when the fetch fails, so a caller about to write
    /// can refuse instead of treating the failure as an empty roster.
    func fetchStudents(ids: [UUID]) throws -> [CDStudent] {
        guard !ids.isEmpty else { return [] }
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = NSPredicate(format: "id IN %@", ids)
        return try context.fetch(request)
    }

    // MARK: - Create

    /// Create a new CDStudent and insert into context
    @discardableResult
    func createStudent(
        firstName: String,
        lastName: String,
        birthday: Date,
        nickname: String? = nil,
        level: CDStudent.Level = .lower,
        dateStarted: Date = Date(),
        bornAfterSunset: Bool = false
    ) -> CDStudent {
        let student = CDStudent(context: context)
        student.firstName = firstName
        student.lastName = lastName
        student.birthday = birthday
        student.nickname = nickname
        student.level = level
        student.dateStarted = dateStarted
        student.bornAfterSunset = bornAfterSunset
        return student
    }

    // MARK: - Update

    /// Update an existing CDStudent's properties. An edit that changes something stamps
    /// `modifiedAt`, which `ClassroomShareRelease` reads to keep the newer of two copies.
    ///
    /// Status and last day are written together (`updateEnrollment`): a child
    /// leaving runs the departure cascade unless `carryOutDeparture` is false
    /// (the student page's Keep Plans), and one coming back gets back the
    /// year-plan entries her departure skipped.
    @discardableResult
    func updateStudent(
        id: UUID,
        firstName: String? = nil,
        lastName: String? = nil,
        birthday: Date? = nil,
        nickname: String? = nil,
        level: CDStudent.Level? = nil,
        dateStarted: Date? = nil,
        enrollmentStatus: CDStudent.EnrollmentStatus? = nil,
        dateWithdrawn: Date?? = nil,
        bornAfterSunset: Bool? = nil,
        carryOutDeparture: Bool = true,
        ledger: DepartureSkipLedger = .synced
    ) -> Bool {
        guard let student = fetchStudent(id: id) else { return false }
        let before = student.dictionaryWithValues(forKeys: Self.editableKeys) as NSDictionary

        if let firstName { student.firstName = firstName }
        if let lastName { student.lastName = lastName }
        if let birthday { student.birthday = birthday }
        if let nickname { student.nickname = nickname.isEmpty ? nil : nickname }
        if let level, level != student.level {
            // Record the move so the profile can show "Promoted · Lower → Upper on <date>".
            student.previousLevelRaw = student.levelRaw
            student.dateLastPromoted = Date()
            student.level = level
        }
        if let dateStarted { student.dateStarted = dateStarted }
        if enrollmentStatus != nil || dateWithdrawn != nil {
            updateEnrollment(
                student, status: enrollmentStatus ?? student.enrollmentStatus,
                lastDay: dateWithdrawn ?? student.dateWithdrawn,
                carryOutDeparture: carryOutDeparture, ledger: ledger
            )
        }
        Self.set(bornAfterSunset: bornAfterSunset, on: student)

        if !before.isEqual(to: student.dictionaryWithValues(forKeys: Self.editableKeys)) {
            student.modifiedAt = Date()
        }
        return true
    }

    /// What a change of status or last day did beyond the two fields.
    struct EnrollmentChange: Equatable {
        /// The departure cascade's report, when she left (or her last day moved).
        var departure: StudentDeparture.Report?
        /// Year-plan entries given back to her when she came back.
        var entriesRestored = 0
    }

    /// Writes her status and last day together, the one place they change
    /// (domain logic review R7). Back to enrolled clears the last day and
    /// un-skips the entries her departure skipped (`StudentDeparture.returning`).
    /// Leaving without a last day takes today as the last one. Leaving, or a
    /// departed child's last day moving, runs the departure cascade
    /// (`StudentDeparture.carryOut`) unless `carryOutDeparture` is false.
    /// Does not save.
    @discardableResult
    func updateEnrollment(
        _ student: CDStudent, status: CDStudent.EnrollmentStatus, lastDay: Date?,
        carryOutDeparture: Bool = true, now: Date = Date(), ledger: DepartureSkipLedger = .synced
    ) -> EnrollmentChange {
        let wasStatus = student.enrollmentStatus
        let wasLastDay = student.dateWithdrawn
        var change = EnrollmentChange()
        student.enrollmentStatus = status
        guard status != .enrolled else {
            student.dateWithdrawn = nil
            if wasStatus != .enrolled, let id = student.id {
                change.entriesRestored = StudentDeparture.returning(studentID: id, in: context, ledger: ledger)
            }
            return change
        }
        // Today stands in only when she leaves now: a departed child saved
        // again with no date keeps none, so she stays out of past rolls.
        student.dateWithdrawn = lastDay ?? wasLastDay ?? (wasStatus == .enrolled ? now : nil)
        let moved = wasStatus == .enrolled || student.dateWithdrawn != wasLastDay
        if moved, carryOutDeparture, let id = student.id {
            change.departure = StudentDeparture.carryOut(
                studentID: id, lastDay: student.dateWithdrawn, in: context, now: now, ledger: ledger
            )
        }
        return change
    }

    /// The attributes `updateStudent` can change.
    private static let editableKeys = [
        "firstName", "lastName", "birthday", "nickname", "levelRaw", "dateStarted", "enrollmentStatusRaw",
        "dateWithdrawn", "bornAfterSunset"
    ]

    /// Sets the "Born after sunset" switch when it differs. Compared first: a
    /// child stored before schema 21 holds no value, which reads as false, and
    /// writing false over it would stamp an edit nobody made.
    private static func set(bornAfterSunset: Bool?, on student: CDStudent) {
        guard let bornAfterSunset, bornAfterSunset != student.bornAfterSunset else { return }
        student.bornAfterSunset = bornAfterSunset
    }

    // MARK: - Delete

    /// Deletes a student and everything that is hers alone, and takes her off
    /// every record she shares (`StudentDeletion`). The deletion is saved on
    /// its own: edits already pending are saved first, so a failed save can
    /// discard exactly the deletion's changes (`WorkDeletionService` runs
    /// transactions of its own inside it, which an outer undo group can't
    /// roll back). Her documents' files are removed only once it has saved.
    @discardableResult
    func deleteStudent(id: UUID) throws -> StudentDeletionReport {
        guard fetchStudent(id: id) != nil else { return StudentDeletionReport() }
        if context.hasChanges { try context.save() }
        let report = StudentDeletion.deleteEverything(for: id, in: context)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        for url in report.documentFiles {
            try? StudentDocumentFileStorage.deleteIfManaged(url)
        }
        return report
    }
}
