import SwiftUI
import MessageUI

/// Opens the front-desk email and records it when it goes.
///
/// With Apple's Mail set up, the email opens in Mail's sheet, and "sent" is
/// recorded when Mail says so. Without it, the email opens in whatever Mail
/// app the phone uses, which can't report back, so she's asked whether it
/// went. A tapped front-desk reminder opens it too, for today, unless someone
/// has already sent it (the bar then shows who).
///
/// A modifier of its own so the attendance screen only bumps `requests`.
struct AssistantFrontDeskMail: ViewModifier {
    let viewModel: AssistantAttendanceViewModel?
    /// Bumped by the bar's Email the Front Desk and Send Again.
    let requests: Int

    @State private var draft: AttendanceEmailDraft?
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
                    if result == .sent { viewModel?.frontDesk.recordSend(confirmedByHand: false) }
                }
                .ignoresSafeArea()
            }
            .alert("Did the email go?", isPresented: $askingWhetherSent) {
                Button("It Went") { viewModel?.frontDesk.recordSend(confirmedByHand: true) }
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
    /// question first (`reminderAction`).
    private func openForReminder() {
        guard FrontDeskEmailReminder.isEmailRequested, let viewModel else { return }
        FrontDeskEmailReminder.isEmailRequested = false
        viewModel.load(Date())
        let action = Self.reminderAction(
            alreadySent: viewModel.frontDesk.latestSend != nil,
            isOffered: viewModel.frontDesk.isOffered(by: viewModel),
            unmarked: viewModel.unmarkedCount,
            canClose: viewModel.canMark && viewModel.phase == .arrival
        )
        switch action {
        case .nothing: break
        case .openEmail: open()
        case .askToClose: viewModel.asksToCloseAndEmail = true
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
}
