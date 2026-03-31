import Foundation
import CoreData
import OSLog

// MARK: - Students

extension BackupEntityImporter {

    /// Imports students from DTOs, returning a dictionary of imported students by ID.
    static func importStudents(
        _ dtos: [StudentDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDStudent>
    ) rethrows -> [UUID: CDStudent] {
        var studentsByID: [UUID: CDStudent] = [:]
        for dto in dtos {
            do {
                if try existingCheck(dto.id) != nil { continue }
            } catch {
                let desc = error.localizedDescription
                Logger.backup.warning("Failed to check existing student: \(desc, privacy: .public)")
                continue
            }
            let student = CDStudent(context: viewContext)
            student.id = dto.id
            student.firstName = dto.firstName
            student.lastName = dto.lastName
            student.birthday = dto.birthday
            student.level = dto.level == .upper ? .upper : .lower
            student.dateStarted = dto.dateStarted
            student.nextLessons = dto.nextLessons.map(\.uuidString) as NSArray
            student.manualOrder = Int64(dto.manualOrder)
            viewContext.insert(student)
            studentsByID[student.id ?? dto.id] = student
        }
        return studentsByID
    }
}
