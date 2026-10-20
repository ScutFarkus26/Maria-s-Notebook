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
    /// The day's sends as the bar's line words them: who sent it first and
    /// whether that was on time, then "sent again" (bug hunt 2026-10-20, #15).
    private(set) var daySends: AttendanceEmailLog.DaySends?
    /// ParentLocker said it isn't expecting the day's attendance, on this
    /// phone or another: nothing to send (#19).
    private(set) var isNotExpected = false
    /// A tapped reminder is waiting for iCloud to catch up before it opens
    /// anything: the bar says "Checking whether it's gone…" (#14).
    private(set) var isCheckingForSend = false
    /// Set when recording a send couldn't be saved, or Mail said the email
    /// didn't go; cleared by the next send recorded, a newer send arriving
    /// from another phone, or another day.
    private(set) var errorMessage: String?
    /// Bumped by each send recorded here, so the reminder is withdrawn.
    private(set) var sendsRecorded = 0

    private var date = Date.distantPast
    /// The day's newest send when `errorMessage` was set: a newer one means
    /// the email has gone since.
    @ObservationIgnored private var sendAtError: AttendanceEmailLog.Send?
    @ObservationIgnored private let context: NSManagedObjectContext
    @ObservationIgnored private let container: NSPersistentCloudKitContainer?

    init(context: NSManagedObjectContext, container: NSPersistentCloudKitContainer?) {
        self.context = context
        self.container = container
    }

    /// Reads `day`'s send and the guide's settings; the attendance screen's
    /// every load (a day change, an import) calls it. The error line goes
    /// with another day, or once a send newer than the error is in: "The
    /// email didn't send" used to stay under the line saying another
    /// assistant had sent it (review of the 2026-10-20 fixes).
    func load(_ day: Date) {
        let isAnotherDay = !Calendar.current.isDate(day, inSameDayAs: date)
        date = day
        settings = AttendanceEmailLog.settings(in: context)
        latestSend = AttendanceEmailLog.latestSend(on: day, in: context)
        daySends = AttendanceEmailLog.daySends(on: day, in: context)
        isNotExpected = settings?.sendMethod == .parentLocker
            && AttendanceEmailLog.isNotExpected(on: day, in: context)
        if isAnotherDay || (latestSend != nil && latestSend != sendAtError) { errorMessage = nil }
    }

    /// Waits, after a reminder tap that brought the app forward, for the
    /// first import into the classroom's store or `limit`, whichever comes
    /// first, saying so on the bar meanwhile (bug hunt 2026-10-20, #14). The
    /// phone's copy can be behind after a while away: another assistant's
    /// send hadn't arrived, the tap opened the email again, and the front
    /// desk got it twice.
    func waitForCatchUp(limit: Duration, firstImport: @escaping @Sendable () async -> Void) async {
        isCheckingForSend = true
        defer { isCheckingForSend = false }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await firstImport() }
            group.addTask { try? await Task.sleep(for: limit) }
            await group.next()
            group.cancelAll()
        }
    }

    /// Mail said the email didn't go (#20): the bar says so, plainly.
    func mailFailed() {
        showError("The email didn't send. Try again.")
    }

    private func showError(_ message: String) {
        errorMessage = message
        sendAtError = latestSend
    }

    /// Whether the bar offers the email: the guide has set it up, and the day
    /// has a class that has arrived (not a day off or a day ahead).
    func isOffered(by viewModel: AssistantAttendanceViewModel) -> Bool {
        settings?.canSend == true && viewModel.dayOff == nil && !viewModel.rows.isEmpty && !viewModel.isFuture
    }

    /// The guide's due time, in minutes after midnight.
    var deadlineMinutes: Int {
        settings?.deadlineMinutes ?? AttendanceEmailLog.defaultDeadlineMinutes
    }

    /// The two moments on `day` the bar's email line changes: half an hour
    /// before the due time, and at it.
    func changeTimes(on day: Date) -> [Date] {
        AttendanceEmailLog.changeTimes(on: day, deadlineMinutes: deadlineMinutes)
    }

    /// Whether the bar offers Close Arrival & Email: the email is due or
    /// late, nobody has sent it, and children are still unmarked during
    /// arrival on a day she can mark. The plain Close Arrival steps aside
    /// then, and the email button's question offers closing without it.
    /// Not while a tapped reminder checks whether it's gone: the email line
    /// says so then, and the plain Close Arrival stays (review of the
    /// 2026-10-20 fixes; it used to vanish for the whole wait).
    func offersCloseAndEmail(by viewModel: AssistantAttendanceViewModel, now: Date = Date()) -> Bool {
        !isCheckingForSend && isOffered(by: viewModel) && latestSend == nil && viewModel.unmarkedCount > 0
            && viewModel.canMark && viewModel.phase == .arrival
            && AttendanceEmailLog.urgency(for: viewModel.date, deadlineMinutes: deadlineMinutes, now: now) != .none
    }

    /// The day's email in the guide's format: on time, tardy, left early and
    /// absent, as the notebook writes it. A child who arrived late and then
    /// left is under Left Early, "(arrived late)".
    func draft(for rows: [AssistantAttendanceViewModel.Row]) -> AttendanceEmailDraft? {
        guard let settings, settings.canSend else { return nil }
        let cameLate = AttendanceEmailStudent.lateThenLeftEarly(on: date, in: context)
        func students(_ status: AttendanceStatus) -> [AttendanceEmailStudent] {
            rows.filter { $0.status == status && !$0.studentIsGone }.map { row in
                AttendanceEmailStudent(row.student, arrivedLate: cameLate.contains(row.id.uuidString))
            }
        }
        return settings.draft(
            for: date, present: students(.present), tardy: students(.tardy), absent: students(.absent),
            leftEarly: students(.leftEarly)
        )
    }

    /// Records that the day's email went, saved like a mark and put in the
    /// share. `confirmedByHand` when Mail couldn't say (another Mail app), or
    /// the front desk was told another way. `day` is the day the email was
    /// written for, which the grid may have left since (a tapped reminder
    /// moves it to today; #20); nil for the day on screen.
    func recordSend(confirmedByHand: Bool, on day: Date? = nil) {
        let day = day ?? date
        let send = AttendanceEmailLog.recordSend(
            on: day, role: .assistant, confirmedByHand: confirmedByHand, in: context
        )
        guard AssistantSave.save(context, container: container, created: [send]) else {
            // Not left waiting for the next mark's save, which wouldn't put
            // it in the share.
            context.delete(send)
            showError("Couldn't record that the email was sent. Try again.")
            return
        }
        errorMessage = nil
        sendsRecorded += 1
        guard Calendar.current.isDate(day, inSameDayAs: date) else { return }
        latestSend = AttendanceEmailLog.Send(send)
        daySends = AttendanceEmailLog.daySends(on: date, in: context)
    }
}
