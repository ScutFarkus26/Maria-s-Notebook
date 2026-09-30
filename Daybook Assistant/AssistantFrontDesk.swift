import Foundation
import CoreData
import Observation

/// The front-desk attendance email for the day on screen.
///
/// The guide sets the email up in the notebook (recipients and report
/// format), and the notebook puts those settings in the classroom share
/// (`AttendanceEmailLog`). Here the email is offered once everyone's marked,
/// written in the guide's format, and when it goes a record of it goes into
/// the share, so the guide and the other assistants see "Sent 8:42 by Sarah"
/// and nobody sends it twice.
@MainActor
@Observable
final class AssistantFrontDesk {

    /// The guide's settings, once the notebook has put them in the share.
    private(set) var settings: AttendanceEmailLog.Settings?
    /// The day's newest send, from this phone or anyone else's.
    private(set) var latestSend: AttendanceEmailLog.Send?
    /// Set when recording a send couldn't be saved; cleared by the next that can.
    private(set) var errorMessage: String?
    /// Bumped by each send recorded here, so the reminder is withdrawn.
    private(set) var sendsRecorded = 0

    private var date = Date.distantPast
    @ObservationIgnored private let context: NSManagedObjectContext
    @ObservationIgnored private let container: NSPersistentCloudKitContainer?

    init(context: NSManagedObjectContext, container: NSPersistentCloudKitContainer?) {
        self.context = context
        self.container = container
    }

    /// Reads `day`'s send and the guide's settings; the attendance screen's
    /// every load (a day change, an import) calls it.
    func load(_ day: Date) {
        date = day
        settings = AttendanceEmailLog.settings(in: context)
        latestSend = AttendanceEmailLog.latestSend(on: day, in: context)
    }

    /// Whether the bar offers the email: the guide has set it up, and the day
    /// has a class that has arrived (not a day off or a day ahead).
    func isOffered(by viewModel: AssistantAttendanceViewModel) -> Bool {
        settings?.canSend == true && viewModel.dayOff == nil && !viewModel.rows.isEmpty && !viewModel.isFuture
    }

    /// The day's email in the guide's format: on time, tardy and absent, as
    /// the notebook writes it.
    func draft(for rows: [AssistantAttendanceViewModel.Row]) -> AttendanceEmailDraft? {
        guard let settings, settings.canSend else { return nil }
        func students(_ status: AttendanceStatus) -> [AttendanceEmailStudent] {
            rows.filter { $0.status == status }.map { AttendanceEmailStudent($0.student) }
        }
        return settings.draft(
            for: date, present: students(.present), tardy: students(.tardy), absent: students(.absent)
        )
    }

    /// Records that the day's email went, saved like a mark and put in the
    /// share. `confirmedByHand` when Mail couldn't say (another Mail app), or
    /// the front desk was told another way.
    func recordSend(confirmedByHand: Bool) {
        let send = AttendanceEmailLog.recordSend(
            on: date, role: .assistant, confirmedByHand: confirmedByHand, in: context
        )
        guard AssistantSave.save(context, container: container, created: [send]) else {
            // Not left waiting for the next mark's save, which wouldn't put
            // it in the share.
            context.delete(send)
            errorMessage = "Couldn't save that the email went. Try again."
            return
        }
        errorMessage = nil
        latestSend = AttendanceEmailLog.Send(send)
        sendsRecorded += 1
    }
}
