//
//  StudentRepository.swift
//  Maria's Notebook
//
//  Repository for Student entity CRUD operations.
//  Follows the pattern established by WorkRepository.
//

import Foundation
import OSLog
import SwiftData

@MainActor
struct StudentRepository: SavingRepository {
    typealias Model = Student

    private static let logger = Logger.database

    let context: ModelContext
    let saveCoordinator: SaveCoordinator?

    init(context: ModelContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch

    /// Fetch a Student by ID
    func fetchStudent(id: UUID) -> Student? {
        var descriptor = FetchDescriptor<Student>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return context.safeFetchFirst(descriptor)
    }

    /// Fetch multiple Students with optional filtering and sorting
    /// - Parameters:
    ///   - predicate: Optional predicate to filter students. If nil, fetches all.
    ///   - sortBy: Optional sort descriptors. Defaults to sorting by lastName, firstName.
    /// - Returns: Array of Student entities matching the criteria
    func fetchStudents(
        predicate: Predicate<Student>? = nil,
        sortBy: [SortDescriptor<Student>] = [
            SortDescriptor(\.lastName),
            SortDescriptor(\.firstName)
        ]
    ) -> [Student] {
        var descriptor = FetchDescriptor<Student>()
        if let predicate {
            descriptor.predicate = predicate
        }
        descriptor.sortBy = sortBy
        return context.safeFetch(descriptor)
    }

    // MARK: - Create

    /// Create a new Student and insert into context
    /// - Parameters:
    ///   - firstName: Student's first name
    ///   - lastName: Student's last name
    ///   - birthday: Student's birthday
    ///   - nickname: Optional nickname
    ///   - level: Student's level (lower/upper). Defaults to .lower
    ///   - dateStarted: Date the student started. Defaults to current date.
    /// - Returns: The created Student entity
    @discardableResult
    func createStudent(
        firstName: String,
        lastName: String,
        birthday: Date,
        nickname: String? = nil,
        level: Student.Level = .lower,
        dateStarted: Date = Date()
    ) -> Student {
        let student = Student(
            firstName: firstName,
            lastName: lastName,
            birthday: birthday,
            nickname: nickname,
            level: level,
            dateStarted: dateStarted
        )
        context.insert(student)
        return student
    }

    // MARK: - Update

    /// Update an existing Student's properties
    /// - Parameters:
    ///   - id: The UUID of the student to update
    ///   - firstName: New first name (optional)
    ///   - lastName: New last name (optional)
    ///   - birthday: New birthday (optional)
    ///   - nickname: New nickname (optional, pass empty string to clear)
    ///   - level: New level (optional)
    ///   - dateStarted: New start date (optional)
    /// - Returns: true if update succeeded, false if student not found
    @discardableResult
    func updateStudent(
        id: UUID,
        firstName: String? = nil,
        lastName: String? = nil,
        birthday: Date? = nil,
        nickname: String? = nil,
        level: Student.Level? = nil,
        dateStarted: Date? = nil,
        enrollmentStatus: Student.EnrollmentStatus? = nil,
        dateWithdrawn: Date?? = nil
    ) -> Bool {
        guard let student = fetchStudent(id: id) else { return false }

        if let firstName {
            student.firstName = firstName
        }
        if let lastName {
            student.lastName = lastName
        }
        if let birthday {
            student.birthday = birthday
        }
        if let nickname {
            student.nickname = nickname.isEmpty ? nil : nickname
        }
        if let level {
            student.level = level
        }
        if let dateStarted {
            student.dateStarted = dateStarted
        }
        if let enrollmentStatus {
            student.enrollmentStatus = enrollmentStatus
        }
        if let dateWithdrawn {
            student.dateWithdrawn = dateWithdrawn
        }

        return true
    }

    /// Withdraw a student, setting their status to withdrawn and recording the date
    @discardableResult
    func withdrawStudent(id: UUID, date: Date = Date()) -> Bool {
        guard let student = fetchStudent(id: id) else { return false }
        student.enrollmentStatus = .withdrawn
        student.dateWithdrawn = date
        return true
    }

    /// Re-enroll a withdrawn student, clearing their withdrawal date
    @discardableResult
    func reenrollStudent(id: UUID) -> Bool {
        guard let student = fetchStudent(id: id) else { return false }
        student.enrollmentStatus = .enrolled
        student.dateWithdrawn = nil
        return true
    }

    // MARK: - Delete

    /// Delete a Student by ID
    func deleteStudent(id: UUID) throws {
        guard let student = fetchStudent(id: id) else { return }
        context.delete(student)
        do {
            try context.save()
        } catch {
            Self.logger.warning("Failed to save context: \(error, privacy: .public)")
            throw error
        }
    }
}
