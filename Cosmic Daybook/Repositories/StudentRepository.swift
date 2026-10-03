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
        dateStarted: Date = Date()
    ) -> CDStudent {
        let student = CDStudent(context: context)
        student.firstName = firstName
        student.lastName = lastName
        student.birthday = birthday
        student.nickname = nickname
        student.level = level
        student.dateStarted = dateStarted
        return student
    }

    // MARK: - Update

    /// Update an existing CDStudent's properties. An edit that changes something stamps
    /// `modifiedAt`, which `ClassroomShareRelease` reads to keep the newer of two copies.
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
        dateWithdrawn: Date?? = nil
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
        if let enrollmentStatus { student.enrollmentStatus = enrollmentStatus }
        if let dateWithdrawn { student.dateWithdrawn = dateWithdrawn }

        if !before.isEqual(to: student.dictionaryWithValues(forKeys: Self.editableKeys)) {
            student.modifiedAt = Date()
        }
        return true
    }

    /// The attributes `updateStudent` can change.
    private static let editableKeys = [
        "firstName", "lastName", "birthday", "nickname", "levelRaw", "dateStarted", "enrollmentStatusRaw",
        "dateWithdrawn"
    ]

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
