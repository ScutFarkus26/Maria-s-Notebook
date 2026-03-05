import Foundation
import SwiftData

// MARK: - Students

extension BackupEntityImporter {

    /// Imports students from DTOs, returning a dictionary of imported students by ID.
    static func importStudents(
        _ dtos: [StudentDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<Student>
    ) rethrows -> [UUID: Student] {
        var studentsByID: [UUID: Student] = [:]
        for dto in dtos {
            do {
                if try existingCheck(dto.id) != nil { continue }
            } catch {
                print("⚠️ [Backup:\(#function)] Failed to check existing student: \(error)")
                continue
            }
            let student = Student(
                id: dto.id,
                firstName: dto.firstName,
                lastName: dto.lastName,
                birthday: dto.birthday,
                level: dto.level == .upper ? .upper : .lower
            )
            student.dateStarted = dto.dateStarted
            student.nextLessons = dto.nextLessons.uuidStrings
            student.manualOrder = dto.manualOrder
            modelContext.insert(student)
            studentsByID[student.id] = student
        }
        return studentsByID
    }
}
