import Foundation
import CoreData
import OSLog
import Observation

/// Today's roster paired with whatever attendance record exists for each
/// student, if any.
///
/// Rows are *virtual* until marked: a student with no record yet shows as
/// unmarked without anything being inserted. Inserting a roster-wide set of
/// blank records on screen-open is what produced duplicate floods when two
/// devices opened the same day, and a third device would only make it worse.
@MainActor
@Observable
final class AssistantAttendanceViewModel {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DaybookAssistant",
        category: "attendance"
    )

    struct Row: Identifiable {
        let student: CDStudent
        var record: CDAttendanceRecord?
        var id: UUID { student.id ?? UUID() }
        var status: AttendanceStatus { record?.status ?? .unmarked }
        var absenceReason: AbsenceReason { record?.absenceReason ?? .none }
    }

    private(set) var rows: [Row] = []
    private(set) var errorMessage: String?

    let date: Date
    private let context: NSManagedObjectContext
    private let store: CDAttendanceStore

    init(context: NSManagedObjectContext, date: Date = Date()) {
        self.context = context
        self.date = date
        // The role is hardcoded rather than read from the membership row: this
        // app is only ever used by an assistant, and ClassroomPermissions is
        // what stops a mis-set membership from writing beyond attendance.
        self.store = CDAttendanceStore(context: context, role: .assistant)
    }

    var canMark: Bool {
        ClassroomPermissions.canWrite(entityName: "AttendanceRecord", role: .assistant)
    }

    func load() {
        let request = CDFetchRequest(CDStudent.self)
        request.sortDescriptors = [
            NSSortDescriptor(key: "firstName", ascending: true),
            NSSortDescriptor(key: "lastName", ascending: true)
        ]
        let students = context.safeFetch(request).filter(\.isEnrolled)

        let records: [CDAttendanceRecord]
        do {
            records = try store.loadRecords(for: date).deduplicatedPerStudentDay()
        } catch {
            Self.logger.error("Loading attendance failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Couldn't load today's attendance."
            records = []
        }

        let byStudent = Dictionary(
            records.map { ($0.studentID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        rows = students.map { student in
            Row(student: student, record: byStudent[student.id?.uuidString ?? ""])
        }
    }

    /// Advances one student through present → absent → tardy → left early and
    /// back to unmarked, creating the record on the first mark.
    func cycleStatus(for row: Row) {
        guard canMark else { return }
        do {
            guard let record = try store.ensureRecord(for: row.student, on: date) else { return }
            _ = store.updateStatus(record, to: record.status.next())
            persist()
        } catch {
            Self.logger.error("Marking failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Couldn't save that mark."
        }
    }

    func setAbsenceReason(_ reason: AbsenceReason, for row: Row) {
        guard canMark, let record = row.record else { return }
        _ = store.updateAbsenceReason(record, to: reason)
        persist()
    }

    private func persist() {
        guard context.safeSave() else {
            errorMessage = "Couldn't save. Your marks will retry when you're back online."
            return
        }
        errorMessage = nil
        load()
    }
}
