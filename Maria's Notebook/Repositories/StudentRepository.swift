//
//  StudentRepository.swift
//  Maria's Notebook
//
//  Repository for CDStudent entity CRUD operations.
//

import Foundation
import OSLog
import CoreData

@MainActor
struct StudentRepository: SavingRepository {
    typealias Model = CDStudent

    private static let logger = Logger.database

    let context: NSManagedObjectContext
    let saveCoordinator: SaveCoordinator?

    init(context: NSManagedObjectContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch

    /// Fetch a CDStudent by ID
    func fetchStudent(id: UUID) -> CDStudent? {
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return context.safeFetchFirst(request)
    }

    /// Fetch multiple Students with optional filtering and sorting
    func fetchStudents(
        predicate: NSPredicate? = nil,
        sortBy: [NSSortDescriptor] = [
            NSSortDescriptor(key: "lastName", ascending: true),
            NSSortDescriptor(key: "firstName", ascending: true)
        ]
    ) -> [CDStudent] {
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = predicate
        request.sortDescriptors = sortBy
        return context.safeFetch(request)
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

    /// Update an existing CDStudent's properties
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

        if let firstName { student.firstName = firstName }
        if let lastName { student.lastName = lastName }
        if let birthday { student.birthday = birthday }
        if let nickname { student.nickname = nickname.isEmpty ? nil : nickname }
        if let level { student.level = level }
        if let dateStarted { student.dateStarted = dateStarted }
        if let enrollmentStatus { student.enrollmentStatus = enrollmentStatus }
        if let dateWithdrawn { student.dateWithdrawn = dateWithdrawn }

        return true
    }

    /// Withdraw a student
    @discardableResult
    func withdrawStudent(id: UUID, date: Date = Date()) -> Bool {
        guard let student = fetchStudent(id: id) else { return false }
        student.enrollmentStatus = .withdrawn
        student.dateWithdrawn = date
        return true
    }

    /// Re-enroll a withdrawn student
    @discardableResult
    func reenrollStudent(id: UUID) -> Bool {
        guard let student = fetchStudent(id: id) else { return false }
        student.enrollmentStatus = .enrolled
        student.dateWithdrawn = nil
        return true
    }

    // MARK: - Delete

    /// Delete a CDStudent by ID
    func deleteStudent(id: UUID) throws {
        guard let student = fetchStudent(id: id) else { return }
        context.delete(student)
        try context.save()
    }
}
