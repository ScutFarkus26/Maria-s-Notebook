//
//  StudentRepository.swift
//  Maria's Notebook
//
//  Repository for Student entity CRUD operations.
//  Follows the pattern established by WorkRepository.
//

import Foundation
import SwiftData

@MainActor
struct StudentRepository: SavingRepository {
    typealias Model = Student

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
        return (try? context.fetch(descriptor))?.first
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
        if let predicate = predicate {
            descriptor.predicate = predicate
        }
        descriptor.sortBy = sortBy
        return (try? context.fetch(descriptor)) ?? []
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
        dateStarted: Date? = nil
    ) -> Bool {
        guard let student = fetchStudent(id: id) else { return false }

        if let firstName = firstName {
            student.firstName = firstName
        }
        if let lastName = lastName {
            student.lastName = lastName
        }
        if let birthday = birthday {
            student.birthday = birthday
        }
        if let nickname = nickname {
            student.nickname = nickname.isEmpty ? nil : nickname
        }
        if let level = level {
            student.level = level
        }
        if let dateStarted = dateStarted {
            student.dateStarted = dateStarted
        }

        return true
    }

    // MARK: - Delete

    /// Delete a Student by ID
    func deleteStudent(id: UUID) throws {
        guard let student = fetchStudent(id: id) else { return }
        context.delete(student)
        try context.save()
    }
}
