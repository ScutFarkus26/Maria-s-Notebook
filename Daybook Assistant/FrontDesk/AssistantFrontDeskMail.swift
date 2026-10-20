import SwiftUI
import CoreData
import MessageUI

/// Opens the front-desk email and records it when it goes.
///
/// With Apple's Mail set up, the email opens in Mail's sheet, and "sent" is
/// recorded when Mail says so. Without it, the email opens in whatever Mail
/// app the phone uses, which can't report back, so she's asked whether it
/// went. A tapped front-desk reminder opens it too, for today, unless someone
/// has already sent it (the bar then shows who). A tap that brought the app
/// forward first waits for iCloud to catch up (`reminderActionAfterCatchUp`).
///
/// A modifier of its own so the attendance screen only bumps `requests`.
struct AssistantFrontDeskMail: ViewModifier {
    let viewModel: AssistantAttendanceViewModel?
    /// Bumped by the bar's Email the Front Desk and Send Again.
    let requests: Int

    /// Set by a tapped front-desk reminder (`ArrivalReminderTaps`): the tap
    /// brought the app forward, so this phone may not have heard yet that
    /// someone sent it (bug hunt 2026-10-20, #14).
    @MainActor static var tapBroughtAppForward = false
    /// How long a reminder tap waits for iCloud before it decides anyway.
    static let catchUpLimit: Duration = .seconds(10)
    /// The imports since the app came forward, kept from launch by
    /// `ArrivalReminderTaps`, before the screen is up to listen.
    @MainActor static var catchUp = AssistantCatchUpRecord()

    @State private var draft: AttendanceEmailDraft?
    /// The day the open email was written for: the send is recorded there,
    /// wherever the grid has gone since (#20).
    @State private var emailDay: Date?
    @State private var askingWhetherSent = false
    /// Neither Apple's Mail nor any other email app could take it.
    @State private var noMailApp = false
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content
            .onChange(of: requests) { open() }
            .onReceive(NotificationCenter.default.publisher(for: .frontDeskEmailRequested)) { _ in
                openForReminder()
            }
            .task(id: viewModel == nil) { openForReminder() }
            .sheet(item: $draft) { draft in
                MailComposerView(
                    toRecipients: draft.recipients,
                    subject: draft.subject,
                    body: draft.body,
                    preferredSender: nil
                ) { result, _ in
                    switch result {
                    case .sent: viewModel?.frontDesk.recordSend(confirmedByHand: false, on: emailDay)
                    case .failed: viewModel?.frontDesk.mailFailed()
                    default: break
                    }
                }
                .ignoresSafeArea()
            }
            .alert("Did the email go?", isPresented: $askingWhetherSent) {
                Button("It Went") { viewModel?.frontDesk.recordSend(confirmedByHand: true, on: emailDay) }
                Button("Not Yet", role: .cancel) {}
            } message: {
                Text("If it went, your guide and the other assistants will see that the front desk has it.")
            }
            .alert("No email app", isPresented: $noMailApp) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Set up an email account in Mail (or another email app) on this iPhone to send it, "
                    + "or touch and hold the button to mark it sent if the front desk was told another way.")
            }
    }

    private func open() {
        guard let viewModel, let email = viewModel.frontDesk.draft(for: viewModel.rows) else { return }
        emailDay = viewModel.date
        if MFMailComposeViewController.canSendMail() {
            draft = email
        } else if let url = email.mailtoURL {
            // Ask whether it went only if a Mail app actually opened.
            openURL(url) { accepted in
                if accepted { askingWhetherSent = true } else { noMailApp = true }
            }
        } else {
            noMailApp = true
        }
    }

    /// A tapped reminder: today's email, unless it has gone since. With
    /// children still unmarked, the bar asks its Mark N Absent & Email
    /// question first (`reminderAction`). With ParentLocker picked there's
    /// no email: the bar asks Close Arrival & Send's question, or, with
    /// everyone marked, its line offers Send to ParentLocker. A tap that
    /// brought the app forward decides only once iCloud has caught up (#14).
    private func openForReminder() {
        guard FrontDeskEmailReminder.isEmailRequested, let viewModel else { return }
        FrontDeskEmailReminder.isEmailRequested = false
        let broughtForward = Self.tapBroughtAppForward
        Self.tapBroughtAppForward = false
        // Another tap while one waits: that one answers for both.
        guard !viewModel.frontDesk.isCheckingForSend else { return }
        let storeID = Self.classroomStoreID(of: viewModel.context)
        let waits = Self.waitsForCatchUp(broughtForward: broughtForward, storeID: storeID, record: Self.catchUp)
        Task {
            let action = await Self.reminderActionAfterCatchUp(viewModel: viewModel, broughtForward: waits) {
                await Self.firstImport(into: storeID)
            }
            switch action {
            case .nothing: break
            case .openEmail: if !viewModel.frontDesk.sendsToParentLocker { open() }
            case .askToClose: viewModel.asksToCloseAndEmail = true
            }
        }
    }

    /// What a tapped front-desk reminder does.
    enum ReminderAction: Equatable {
        /// Someone has sent it, or there's no email to send today.
        case nothing
        case openEmail
        /// Ask to mark the unmarked absent first, then open the email.
        case askToClose
    }

    /// The email lists only children marked present, late, absent or left
    /// early, so with any still unmarked it used to go without them. When
    /// she can close arrival, she's asked to mark them absent first; when
    /// she can't (a locked day, arrival already closed), it opens as it is.
    static func reminderAction(alreadySent: Bool, isOffered: Bool, unmarked: Int, canClose: Bool) -> ReminderAction {
        guard !alreadySent, isOffered else { return .nothing }
        return unmarked > 0 && canClose ? .askToClose : .openEmail
    }

    /// What a tapped reminder does about the day on screen.
    static func reminderAction(for viewModel: AssistantAttendanceViewModel) -> ReminderAction {
        let frontDesk = viewModel.frontDesk
        return reminderAction(
            alreadySent: frontDesk.latestSend != nil,
            isOffered: frontDesk.sendsToParentLocker
                ? frontDesk.offersParentLocker(by: viewModel) : frontDesk.isOffered(by: viewModel),
            unmarked: viewModel.unmarkedCount,
            canClose: viewModel.canMark && viewModel.phase == .arrival
        )
    }

    /// What a tapped reminder does, once this phone has caught up (bug hunt
    /// 2026-10-20, #14). A tap that brought the app forward found the phone's
    /// copy as it was when she last looked: another assistant's send not in
    /// yet, the email opened again, and the front desk got it twice. So that
    /// tap waits for `firstImport` (the first import into the classroom's
    /// store) or `limit`, whichever comes first, with the bar saying "Checking
    /// whether it's gone…", then reads the day again. A tap with the app
    /// already open decides at once. Nothing, if she has moved to another day
    /// meanwhile.
    static func reminderActionAfterCatchUp(
        viewModel: AssistantAttendanceViewModel,
        broughtForward: Bool,
        now: Date = Date(),
        limit: Duration = catchUpLimit,
        firstImport: @escaping @Sendable () async -> Void
    ) async -> ReminderAction {
        viewModel.load(now)
        guard broughtForward else { return reminderAction(for: viewModel) }
        let day = viewModel.date
        await viewModel.frontDesk.waitForCatchUp(limit: limit, firstImport: firstImport)
        guard viewModel.date == day else { return .nothing }
        viewModel.load()
        return reminderAction(for: viewModel)
    }

    /// Whether a tapped reminder waits for iCloud: it brought the app
    /// forward, and no import into the classroom's store has begun since and
    /// finished (`record`). On a launch from the tap that import often
    /// finished before the screen was up to hear it, and every such tap
    /// waited out the whole limit (review of the 2026-10-20 fixes). The
    /// Sample Class has no store to wait for.
    static func waitsForCatchUp(broughtForward: Bool, storeID: String?, record: AssistantCatchUpRecord) -> Bool {
        guard broughtForward, let storeID else { return false }
        return !record.hasImported(into: storeID)
    }

    /// Returns once an import into the store `storeID` names has finished;
    /// at once with no such store (the Sample Class, which has no iCloud),
    /// or when one finished after the tap looked and before this listened.
    nonisolated static func firstImport(into storeID: String?) async {
        guard let storeID else { return }
        let events = NotificationCenter.default
            .notifications(named: NSPersistentCloudKitContainer.eventChangedNotification)
        if await MainActor.run(body: { catchUp.hasImported(into: storeID) }) { return }
        for await event in events where RemoteImportReloader.isFinishedImport(event, storeIdentifier: storeID) {
            return
        }
    }

    /// The classroom share's store in `context`, as the screen follows its imports.
    static func classroomStoreID(of context: NSManagedObjectContext) -> String? {
        context.persistentStoreCoordinator?.persistentStores
            .first { $0.configurationName == CoreDataStack.sharedConfiguration }?.identifier
    }
}

/// When the app last came forward (launched, or back from the background),
/// and the stores an import began into since then and finished: what a
/// tapped reminder's wait for iCloud needs (`waitsForCatchUp`). An import
/// already going when the app went away doesn't count; it may hold nothing
/// from while she was away.
struct AssistantCatchUpRecord {
    private(set) var forwardSince: Date
    private var caughtUp: Set<String> = []

    init(forwardSince: Date = Date()) {
        self.forwardSince = forwardSince
    }

    /// The app came forward at `date`: what came in before may be behind.
    mutating func cameForward(at date: Date) {
        forwardSince = date
        caughtUp = []
    }

    /// An import into `storeID` that began at `startedAt` finished and worked.
    mutating func importFinished(into storeID: String, startedAt: Date) {
        guard startedAt >= forwardSince else { return }
        caughtUp.insert(storeID)
    }

    func hasImported(into storeID: String) -> Bool {
        caughtUp.contains(storeID)
    }
}
