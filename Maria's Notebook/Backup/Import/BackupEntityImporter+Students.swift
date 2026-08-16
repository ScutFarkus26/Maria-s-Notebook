import Foundation
import CoreData
import OSLog

// MARK: - Students

extension BackupEntityImporter {

    /// Imports students from DTOs, returning a dictionary of imported students by ID.
    static func importStudents(
        _ dtos: [StudentDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck
    ) rethrows -> [UUID: CDStudent] {
        var studentsByID: [UUID: CDStudent] = [:]
        for dto in dtos {
            do {
                if try existingCheck(dto.id) { continue }
            } catch {
                let desc = error.localizedDescription
                Logger.backup.warning("Failed to check existing student: \(desc, privacy: .public)")
                continue
            }
            let student = CDStudent(context: viewContext)
            student.id = dto.id
            student.firstName = dto.firstName
            student.lastName = dto.lastName
            // Older backups fabricated a birthday for students who had none
            // (.distantPast from one transformer). Restore that sentinel as nil
            // rather than a bogus real date. (Backups where the fabricated value
            // was the export-time Date() are indistinguishable from real data.)
            student.birthday = dto.birthday == .distantPast ? nil : dto.birthday
            switch dto.level {
            case .lower: student.level = .lower
            case .upper: student.level = .upper
            case .adolescent: student.level = .adolescent
            }
            student.dateStarted = dto.dateStarted
            student.nextLessons = dto.nextLessons.map(\.uuidString) as NSArray
            student.manualOrder = Int64(dto.manualOrder)
            student.nickname = dto.nickname
            if let v = dto.enrollmentStatusRaw { student.enrollmentStatusRaw = v }
            student.dateWithdrawn = dto.dateWithdrawn
            student.previousLevelRaw = dto.previousLevelRaw
            student.dateLastPromoted = dto.dateLastPromoted
            // Preserve the original modification time (awakeFromInsert stamped "now");
            // older backups lack the field, so those keep the import-time stamp.
            if let v = dto.modifiedAt { student.modifiedAt = v }
            viewContext.insert(student)
            studentsByID[student.id ?? dto.id] = student
        }
        return studentsByID
    }
}
