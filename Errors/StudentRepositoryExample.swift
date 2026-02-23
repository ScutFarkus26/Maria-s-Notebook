//
//  StudentRepositoryExample.swift
//  Maria's Notebook
//
//  Example of StudentRepository enhanced with domain errors.
//  This demonstrates the migration pattern - compare with the original StudentRepository.swift
//
//  Created by Architecture Migration on 2026-02-13.
//

import Foundation
import SwiftData

/// Enhanced StudentRepository with domain error handling
/// This is an EXAMPLE showing how to migrate StudentRepository to use domain errors.
/// DO NOT use this in production yet - it's a reference implementation.
@MainActor
struct StudentRepositoryWithDomainErrors: SavingRepository {
    typealias Model = Student
    
    let context: ModelContext
    let saveCoordinator: SaveCoordinator?
    
    init(context: ModelContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }
    
    // MARK: - Fetch
    
    /// Fetch a Student by ID
    /// - Throws: StudentError.notFound if student doesn't exist
    func fetchStudent(id: UUID) throws -> Student {
        var descriptor = FetchDescriptor<Student>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        
        guard let student = (try? context.fetch(descriptor))?.first else {
            throw StudentError.notFound(id: id)
        }
        
        return student
    }
    
    /// Fetch multiple Students with optional filtering and sorting
    /// - Throws: DatabaseError if fetch fails
    func fetchStudents(
        predicate: Predicate<Student>? = nil,
        sortBy: [SortDescriptor<Student>] = [
            SortDescriptor(\.lastName),
            SortDescriptor(\.firstName)
        ]
    ) throws -> [Student] {
        var descriptor = FetchDescriptor<Student>()
        if let predicate = predicate {
            descriptor.predicate = predicate
        }
        descriptor.sortBy = sortBy
        
        do {
            return try context.fetch(descriptor)
        } catch {
            throw DatabaseError(
                operation: "fetch students",
                entity: "Student",
                underlying: error
            )
        }
    }
    
    // MARK: - Create
    
    /// Create a new Student and insert into context
    /// - Throws: StudentError for validation failures, DatabaseError for persistence failures
    @discardableResult
    func createStudent(
        firstName: String,
        lastName: String,
        birthday: Date,
        nickname: String? = nil,
        level: Student.Level = .lower,
        dateStarted: Date = Date()
    ) throws -> Student {
        // Validation
        guard !firstName.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw StudentError.missingRequiredField(field: "First Name")
        }
        
        guard !lastName.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw StudentError.missingRequiredField(field: "Last Name")
        }
        
        guard birthday <= Date() else {
            throw StudentError.invalidBirthdate(date: birthday)
        }
        
        // Business rule: Check for duplicate names
        if try checkDuplicateName(firstName: firstName, lastName: lastName) {
            throw StudentError.duplicateName(firstName: firstName, lastName: lastName)
        }
        
        // Create student
        let student = Student(
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            lastName: lastName.trimmingCharacters(in: .whitespaces),
            birthday: birthday,
            nickname: nickname?.trimmingCharacters(in: .whitespaces),
            level: level,
            dateStarted: dateStarted
        )
        
        context.insert(student)
        
        // Save immediately to validate
        do {
            try context.save()
        } catch {
            throw DatabaseError(
                operation: "create student",
                entity: "Student",
                underlying: error
            )
        }
        
        return student
    }
    
    // MARK: - Update
    
    /// Update an existing Student's properties
    /// - Throws: StudentError.notFound if student doesn't exist, validation errors for invalid data
    @discardableResult
    func updateStudent(
        id: UUID,
        firstName: String? = nil,
        lastName: String? = nil,
        birthday: Date? = nil,
        nickname: String? = nil,
        level: Student.Level? = nil,
        dateStarted: Date? = nil
    ) throws {
        let student = try fetchStudent(id: id)
        
        // Validate changes
        if let firstName = firstName {
            guard !firstName.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw StudentError.missingRequiredField(field: "First Name")
            }
            student.firstName = firstName.trimmingCharacters(in: .whitespaces)
        }
        
        if let lastName = lastName {
            guard !lastName.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw StudentError.missingRequiredField(field: "Last Name")
            }
            student.lastName = lastName.trimmingCharacters(in: .whitespaces)
        }
        
        if let birthday = birthday {
            guard birthday <= Date() else {
                throw StudentError.invalidBirthdate(date: birthday)
            }
            student.birthday = birthday
        }
        
        if let nickname = nickname {
            student.nickname = nickname.isEmpty ? nil : nickname.trimmingCharacters(in: .whitespaces)
        }
        
        if let level = level {
            student.level = level
        }
        
        if let dateStarted = dateStarted {
            student.dateStarted = dateStarted
        }
        
        // Check for duplicate names if name changed
        if firstName != nil || lastName != nil {
            if try checkDuplicateName(
                firstName: student.firstName,
                lastName: student.lastName,
                excluding: id
            ) {
                throw StudentError.duplicateName(
                    firstName: student.firstName,
                    lastName: student.lastName
                )
            }
        }
        
        do {
            try context.save()
        } catch {
            throw DatabaseError(
                operation: "update student",
                entity: "Student",
                underlying: error
            )
        }
    }
    
    // MARK: - Delete
    
    /// Delete a Student by ID
    /// - Throws: StudentError for business rule violations, DatabaseError for persistence failures
    func deleteStudent(id: UUID) throws {
        let student = try fetchStudent(id: id)
        
        // Business rule: Check for active lessons
        let lessonCount = countActiveLessons(for: student)
        if lessonCount > 0 {
            throw StudentError.cannotDeleteWithActiveLessons(
                studentName: student.fullName,
                lessonCount: lessonCount
            )
        }
        
        // Business rule: Check for active work
        let workCount = countActiveWork(for: student)
        if workCount > 0 {
            throw StudentError.cannotDeleteWithActiveWork(
                studentName: student.fullName,
                workCount: workCount
            )
        }
        
        // Business rule: Check for notes
        let noteCount = countNotes(for: student)
        if noteCount > 0 {
            throw StudentError.cannotDeleteWithNotes(
                studentName: student.fullName,
                noteCount: noteCount
            )
        }
        
        // Delete student
        context.delete(student)
        
        do {
            try context.save()
        } catch {
            throw DatabaseError(
                operation: "delete student",
                entity: "Student",
                underlying: error
            )
        }
    }
    
    // MARK: - Photo Management
    
    /// Update student photo
    /// - Throws: StudentError.notFound, StudentError.invalidPhotoData, StudentError.photoStorageFailed
    func updatePhoto(studentID: UUID, photoData: Data?) throws {
        let student = try fetchStudent(id: studentID)
        
        if let photoData = photoData {
            // Validate photo data
            #if canImport(UIKit)
            guard UIImage(data: photoData) != nil else {
                throw StudentError.invalidPhotoData
            }
            #elseif canImport(AppKit)
            guard NSImage(data: photoData) != nil else {
                throw StudentError.invalidPhotoData
            }
            #endif
            
            do {
                try PhotoStorageService.savePhoto(data: photoData, for: student.id)
                student.photoPath = PhotoStorageService.photoPath(for: student.id)
            } catch {
                throw StudentError.photoStorageFailed(underlying: error)
            }
        } else {
            // Remove photo
            if student.photoPath != nil {
                PhotoStorageService.deletePhoto(for: student.id)
                student.photoPath = nil
            }
        }
        
        do {
            try context.save()
        } catch {
            throw DatabaseError(
                operation: "update photo",
                entity: "Student",
                underlying: error
            )
        }
    }
    
    // MARK: - Private Helpers
    
    private func checkDuplicateName(
        firstName: String,
        lastName: String,
        excluding: UUID? = nil
    ) throws -> Bool {
        let predicate: Predicate<Student>
        if let excluding = excluding {
            predicate = #Predicate<Student> {
                $0.firstName == firstName &&
                $0.lastName == lastName &&
                $0.id != excluding
            }
        } else {
            predicate = #Predicate<Student> {
                $0.firstName == firstName &&
                $0.lastName == lastName
            }
        }
        
        var descriptor = FetchDescriptor<Student>(predicate: predicate)
        descriptor.fetchLimit = 1
        
        do {
            let matches = try context.fetch(descriptor)
            return !matches.isEmpty
        } catch {
            throw DatabaseError(
                operation: "check duplicate name",
                entity: "Student",
                underlying: error
            )
        }
    }
    
    private func countActiveLessons(for student: Student) -> Int {
        let predicate = #Predicate<StudentLesson> {
            $0.studentID == student.id.uuidString
        }
        
        var descriptor = FetchDescriptor<StudentLesson>(predicate: predicate)
        descriptor.fetchLimit = 1000 // reasonable limit
        
        return (try? context.fetch(descriptor))?.count ?? 0
    }
    
    private func countActiveWork(for student: Student) -> Int {
        // Count work items where this student is a participant
        let predicate = #Predicate<WorkParticipantEntity> {
            $0.studentID == student.id.uuidString
        }
        
        var descriptor = FetchDescriptor<WorkParticipantEntity>(predicate: predicate)
        descriptor.fetchLimit = 1000
        
        return (try? context.fetch(descriptor))?.count ?? 0
    }
    
    private func countNotes(for student: Student) -> Int {
        let predicate = #Predicate<NoteStudentLink> {
            $0.studentID == student.id.uuidString
        }
        
        var descriptor = FetchDescriptor<NoteStudentLink>(predicate: predicate)
        descriptor.fetchLimit = 1000
        
        return (try? context.fetch(descriptor))?.count ?? 0
    }
}

// MARK: - Usage Examples

#if DEBUG
extension StudentRepositoryWithDomainErrors {
    /// Example: Create student with error handling
    static func exampleCreate(context: ModelContext) {
        let repository = StudentRepositoryWithDomainErrors(context: context)
        
        do {
            let student = try repository.createStudent(
                firstName: "Maria",
                lastName: "Montessori",
                birthday: Date(timeIntervalSince1970: -2000000000),
                level: .upper
            )
            print("✅ Created student: \(student.fullName)")
        } catch StudentError.missingRequiredField(let field) {
            print("❌ Missing field: \(field)")
        } catch StudentError.invalidBirthdate(let date) {
            print("❌ Invalid birthdate: \(date)")
        } catch StudentError.duplicateName(let first, let last) {
            print("❌ Duplicate name: \(first) \(last)")
        } catch {
            print("❌ Unexpected error: \(error)")
        }
    }
    
    /// Example: Delete student with business rule validation
    static func exampleDelete(context: ModelContext, studentID: UUID) {
        let repository = StudentRepositoryWithDomainErrors(context: context)
        
        do {
            try repository.deleteStudent(id: studentID)
            print("✅ Student deleted successfully")
        } catch StudentError.notFound {
            print("❌ Student not found")
        } catch StudentError.cannotDeleteWithActiveLessons(let name, let count) {
            print("❌ Cannot delete \(name) - has \(count) active lessons")
            print("💡 Archive or remove lessons first")
        } catch StudentError.cannotDeleteWithActiveWork(let name, let count) {
            print("❌ Cannot delete \(name) - has \(count) active work items")
        } catch {
            print("❌ Unexpected error: \(error)")
        }
    }
}
#endif
