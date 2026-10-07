import CoreData
import Foundation
@testable import CosmicDaybook

/// Shared by the classroom-names suites: fixed times, rows as another device
/// wrote them, stamped marks and sends, and running as a given device.
@MainActor
enum ClassroomNamesTestSupport {

    static func at(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_790_000_000 + seconds)
    }

    /// Runs `body` as the device whose record name is `recordName` (and whose
    /// own name is `displayName`, nothing waiting), then puts this device's
    /// identity back.
    static func asDevice<T>(
        recordName: String?,
        displayName: String? = nil,
        _ body: () throws -> T
    ) rethrows -> T {
        let saved = (
            ClassroomIdentity.currentUserRecordName, ClassroomIdentity.displayName, ClassroomIdentity.nameWaitingAs
        )
        defer {
            ClassroomIdentity.currentUserRecordName = saved.0
            ClassroomIdentity.displayName = saved.1
            ClassroomIdentity.nameWaitingAs = saved.2
        }
        ClassroomIdentity.currentUserRecordName = recordName
        ClassroomIdentity.displayName = displayName
        ClassroomIdentity.nameWaitingAs = nil
        return try body()
    }

    /// `asDevice`, for a body that waits (the name list's writes do). The
    /// suites that use it run serialized, so no other test's identity lands
    /// in between.
    static func asDevice<T>(
        recordName: String?,
        displayName: String? = nil,
        _ body: () async throws -> T
    ) async rethrows -> T {
        let saved = (
            ClassroomIdentity.currentUserRecordName, ClassroomIdentity.displayName, ClassroomIdentity.nameWaitingAs
        )
        defer {
            ClassroomIdentity.currentUserRecordName = saved.0
            ClassroomIdentity.displayName = saved.1
            ClassroomIdentity.nameWaitingAs = saved.2
        }
        ClassroomIdentity.currentUserRecordName = recordName
        ClassroomIdentity.displayName = displayName
        ClassroomIdentity.nameWaitingAs = nil
        return try await body()
    }

    /// A row as a device wrote it: made at `created`, last changed at
    /// `modified` (`created` when nil).
    @discardableResult
    static func person(
        _ recordName: String,
        _ name: String,
        role: CDClassroomMembership.ClassroomRole,
        created: Date,
        modified: Date? = nil,
        id: UUID = UUID(),
        store: NSPersistentStore? = nil,
        in context: NSManagedObjectContext
    ) -> CDClassroomPerson {
        let row = CDClassroomPerson(context: context)
        if let store { context.assign(row, to: store) }
        row.id = id
        row.recordName = recordName
        row.role = role
        row.displayName = name
        row.createdAt = created
        row.modifiedAt = modified ?? created
        return row
    }

    /// A child marked present by `role`, stamped with `id` and `name`.
    static func mark(
        by role: CDClassroomMembership.ClassroomRole,
        id: String?,
        name: String?,
        in context: NSManagedObjectContext
    ) -> AttendanceRow {
        let student = CDStudent(context: context)
        student.id = UUID()
        student.firstName = "Maya"
        student.lastName = "Stone"
        let record = CDAttendanceRecord(context: context)
        record.studentID = student.cloudKitKey
        record.date = Calendar.current.startOfDay(for: Date())
        record.status = .present
        record.recordedBy = role.rawValue
        record.recordedByID = id
        record.recordedByName = name
        return AttendanceRow(student: student, record: record, shortName: "Maya", day: record.date ?? Date())
    }

    /// A front-desk email sent by `role`, stamped with `id` and `name`.
    static func send(
        by role: CDClassroomMembership.ClassroomRole,
        id: String?,
        name: String?,
        in context: NSManagedObjectContext
    ) -> AttendanceEmailLog.Send {
        let record = AttendanceEmailLog.recordSend(on: Date(), role: role, in: context)
        record.sentByID = id
        record.sentByName = name
        return AttendanceEmailLog.Send(record)
    }
}
