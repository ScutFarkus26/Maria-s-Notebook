import Foundation
import CoreData

extension AssistantAttendanceViewModel {

    /// The record's values are copied in when the day loads, not read through
    /// it: a tile handed the same record object after its status changed would
    /// look unchanged to SwiftUI and keep its old color.
    ///
    /// Equatable so that a reload which finds nothing new (most imports touch
    /// other days or other entities, and every return to the app reloads)
    /// leaves `rows` unannounced and the grid undrawn: `@Observable` skips
    /// notifying for an Equatable value set to an equal one. Everything a tile
    /// shows is a copied value here, the names included, so equal rows draw
    /// identically.
    struct Row: Identifiable, Equatable {
        let student: CDStudent
        let id: UUID
        /// The student's full name when the day loaded.
        let name: String
        let status: AttendanceStatus
        let absenceReason: AbsenceReason
        /// The day's note, shared with the guide.
        let note: String
        /// When the current mark was made (for Left Early, the arrival); nil
        /// while unmarked and for marks made on another day.
        let markedAt: Date?
        /// When a Left Early child went home.
        let leftAt: Date?
        /// Who made the mark: role raw value, CloudKit user, and typed name
        /// (assistants only; the guide's marks carry none).
        let recordedBy: String?
        let recordedByID: String?
        let recordedByName: String?
        /// The name on the three-column phone grid: see `AssistantDayRoll.gridNames(for:)`.
        let shortName: String
        /// A birthday or half-birthday on the row's day, for the cake.
        let birthday: AssistantBirthday?
        /// School days away in a row before the row's day, when it's enough
        /// for a welcome back (`AssistantWelcomeBack`).
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
            self.birthday = AssistantBirthday.on(day, birthday: student.birthday)
            self.daysAway = daysAway
            self.id = student.id ?? UUID()
            self.name = student.fullName
            self.status = record?.status ?? .unmarked
            self.absenceReason = record?.absenceReason ?? .none
            self.note = record?.note ?? ""
            self.markedAt = record?.markedAt
            self.leftAt = record?.leftAt
            self.recordedBy = record?.recordedBy
            self.recordedByID = record?.recordedByID
            self.recordedByName = record?.recordedByName
        }
    }
}
