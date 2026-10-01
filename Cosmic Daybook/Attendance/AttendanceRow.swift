import Foundation
import CoreData

/// One child on a day's attendance, with whatever record that day holds for
/// them. Shared by the notebook's roll and the Daybook Assistant's grid.
///
/// The record's values are copied in when the day loads, not read through
/// it: a card handed the same record object after its status changed would
/// look unchanged to SwiftUI and keep its old color.
///
/// Equatable so that a reload which finds nothing new (most imports touch
/// other days or other entities) leaves the rows unannounced and the grid
/// undrawn: `@Observable` skips notifying for an Equatable value set to an
/// equal one. Everything a card shows is a copied value here, the names
/// included, so equal rows draw identically.
struct AttendanceRow: Identifiable, Equatable {
    let student: CDStudent
    let id: UUID
    /// The student's full name when the day loaded.
    let name: String
    let status: AttendanceStatus
    let absenceReason: AbsenceReason
    /// The day's note, shared between the guide and the assistants.
    let note: String
    /// When the current mark was made (for Left Early, the arrival); nil
    /// while unmarked and for marks made on another day.
    let markedAt: Date?
    /// When a Left Early child went home, or, once back, when the trip
    /// out began.
    let leftAt: Date?
    /// When a child who left early came back (Back in Class).
    let returnedAt: Date?
    /// When the child is due to be picked up early ("leaves 1:30").
    let leavesAt: Date?
    /// Who made the mark: role raw value, CloudKit user, and typed name
    /// (assistants only; the guide's marks carry none).
    let recordedBy: String?
    let recordedByID: String?
    let recordedByName: String?
    /// The name on the three-column phone grid: see `AttendanceGridNames`.
    let shortName: String
    /// A birthday or half-birthday on the row's day, for the cake.
    let birthday: AttendanceBirthday?
    /// School days away in a row before the row's day, when it's enough for
    /// a welcome back (the Daybook Assistant's `AttendanceWelcomeBack`).
    let daysAway: Int?

    init(
        student: CDStudent,
        record: CDAttendanceRecord?,
        shortName: String,
        day: Date,
        daysAway: Int? = nil
    ) {
        self.student = student
        self.shortName = shortName
        self.birthday = AttendanceBirthday.on(day, birthday: student.birthday)
        self.daysAway = daysAway
        self.id = student.id ?? UUID()
        self.name = student.fullName
        self.status = record?.status ?? .unmarked
        self.absenceReason = record?.absenceReason ?? .none
        self.note = record?.note ?? ""
        self.markedAt = record?.markedAt
        self.leftAt = record?.leftAt
        self.returnedAt = record?.returnedAt
        self.leavesAt = record?.leavesAt
        self.recordedBy = record?.recordedBy
        self.recordedByID = record?.recordedByID
        self.recordedByName = record?.recordedByName
    }

    /// The student row is gone from the store: deleted here, or by an import (a child the
    /// guide takes out of the classroom share when a school year ends). Nothing may read or
    /// mark it; the next load drops or replaces the row.
    var studentIsGone: Bool {
        student.isDeleted || student.managedObjectContext == nil
    }

    /// Present, late and left early all mean the child came in.
    var isHere: Bool {
        switch status {
        case .present, .tardy, .leftEarly: return true
        case .absent, .unmarked: return false
        }
    }

    /// In the room now: present or late. A child who left early came in but
    /// has gone, so the counts ("17 here") leave them out.
    var isInRoom: Bool {
        status == .present || status == .tardy
    }
}
