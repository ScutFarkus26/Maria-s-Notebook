// AttendanceExpandedView+FrontDesk.swift
// The front-desk attendance email: sending it, recording that it went, and
// the reminder's tap.

import CoreData
import SwiftUI
#if os(iOS)
import MessageUI
#endif

extension AttendanceExpandedView {

    /// Everyone on the day's roll has a mark: the email is worth sending.
    var isRollComplete: Bool {
        !viewModel.rows.isEmpty && viewModel.unmarkedCount == 0
    }

    /// When the front desk needs it by: the guide's setting.
    var deadlineMinutes: Int { Self.deadlineMinutes(in: viewContext) }

    /// The due time as the shared settings row holds it, where the reminder,
    /// the sync and the assistants read it, not this device's synced
    /// preference, which can lag behind it; 9:00 before there is a row.
    static func deadlineMinutes(in context: NSManagedObjectContext) -> Int {
        AttendanceEmailLog.settings(in: context)?.deadlineMinutes ?? AttendanceEmailLog.defaultDeadlineMinutes
    }

    /// The two moments the control changes: half an hour before the due
    /// time, and at it. It's redrawn then and at no other time.
    var frontDeskChangeTimes: [Date] {
        AttendanceEmailLog.changeTimes(on: date, deadlineMinutes: deadlineMinutes)
    }

    var frontDeskControl: some View {
        // Redrawn at the moments it changes, reading the clock each time. Not
        // an explicit TimelineView: once both moments had passed (every day
        // after the due time, and every past day) it redrew every frame.
        RedrawsAt(times: frontDeskChangeTimes) {
            AttendanceFrontDeskControl(
                sentSummary: frontDeskSend.map(frontDeskSummary),
                isRollComplete: isRollComplete,
                urgency: AttendanceEmailLog.urgency(for: date, deadlineMinutes: deadlineMinutes),
                onSend: prepareAttendanceEmail,
                onMarkRestAbsentAndSend: { confirmingRestAbsent = true },
                onMarkSent: { recordFrontDeskSend(confirmedByHand: true) }
            )
        }
    }

    /// Everyone still unmarked goes absent (closing arrival here, as Close
    /// Arrival does), then the email opens.
    func markRestAbsentAndEmail() {
        withAnimation(.smooth(duration: 0.3)) {
            viewModel.markUnmarkedAbsent(modelContext: viewContext)
        }
        saved("Mark the rest absent")
        prepareAttendanceEmail()
    }

    /// On iPhone, where the email is otherwise in the overflow menu: its own
    /// row once everyone's marked, the due time is near, or it has gone.
    /// With ParentLocker picked, ParentLocker's line in its place, and Send
    /// to ParentLocker beside it once everyone's marked and nothing has gone,
    /// as the Mac and iPad have (bug hunt 2026-10-13 afternoon, M2).
    @ViewBuilder
    var compactFrontDeskRow: some View {
        #if os(iOS)
        let urgency = AttendanceEmailLog.urgency(for: date, deadlineMinutes: deadlineMinutes)
        let near = urgency != .none
        if hSizeClass == .compact, sendsToParentLocker, !viewModel.isFuture {
            HStack(spacing: AppTheme.Spacing.small) {
                parentLockerLine(showsProblems: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // A child left out of ParentLocker isn't waited for, as the
                // line doesn't (`AttendanceRow.waitsForParentLocker`).
                if Self.compactRowOffersSend(
                    isOpen: parentLockerIsOpen, isFuture: viewModel.isFuture,
                    isRollComplete: !viewModel.rows.isEmpty && !viewModel.rows.contains(where: \.waitsForParentLocker),
                    isToday: viewModel.isToday
                ) {
                    let overdue = if case .overdue = urgency { true } else { false }
                    parentLockerSendButton(overdue: overdue, prominent: true)
                        .controlSize(.small)
                        .fixedSize()
                }
            }
            .padding(.horizontal, AppTheme.Spacing.compact)
            .padding(.bottom, AppTheme.Spacing.small)
        } else if hSizeClass == .compact, emailIsOn, !isNonSchoolDay, frontDeskSend != nil || isRollComplete || near {
            HStack {
                Spacer(minLength: 0)
                frontDeskControl
                    .controlSize(.small)
            }
            .padding(.horizontal, AppTheme.Spacing.compact)
            .padding(.bottom, AppTheme.Spacing.small)
        }
        #endif
    }

    /// Whether the iPhone's row offers Send to ParentLocker: the day is
    /// still open, is today, and everyone on it is marked. Not another day
    /// (bug hunt 2026-10-20, #17): one tap sent a past day over what the
    /// office had; the ⋯ menu's Send Now asks first.
    static func compactRowOffersSend(isOpen: Bool, isFuture: Bool, isRollComplete: Bool, isToday: Bool) -> Bool {
        isOpen && !isFuture && isRollComplete && isToday
    }

    /// What the 9:00 reminder's tap does on the roll.
    enum ReminderTap: Equatable {
        /// Asks whether to send today's attendance to ParentLocker.
        case offerParentLocker
        /// Opens today's email.
        case openEmail
        case nothing
    }

    /// The reminder's tap: with ParentLocker picked, offers Send while today
    /// is open (bug hunt 2026-10-13 afternoon, M2); with the email, opens it
    /// unless it has gone.
    static func reminderTap(
        sendsToParentLocker: Bool, parentLockerIsOpen: Bool, emailIsOpen: Bool
    ) -> ReminderTap {
        if sendsToParentLocker { return parentLockerIsOpen ? .offerParentLocker : .nothing }
        return emailIsOpen ? .openEmail : .nothing
    }

    /// Who sent the day's email, as this screen reads it ("you" for the
    /// guide's own, an assistant by the name she goes by now): who sent it
    /// first and whether that was on time, with any later send as "· sent
    /// again" (bug hunt 2026-10-20, #15). `send` is the day's newest, read
    /// on its own before the day's sends are.
    func frontDeskSummary(_ send: AttendanceEmailLog.Send) -> String {
        let sends = AttendanceEmailLog.daySends(on: date, in: viewContext)
            ?? AttendanceEmailLog.DaySends(first: send, again: nil)
        let name = sends.first.senderName(
            viewerRole: CDClassroomMembership.currentRole(in: viewContext),
            myRecordName: ClassroomIdentity.currentUserRecordName,
            myName: ClassroomIdentity.displayName,
            names: classroomNames
        )
        return sends.summary(senderName: name, for: date, deadlineMinutes: deadlineMinutes)
    }

    /// Records that the day's attendance went (the email, or with
    /// ParentLocker picked, Mark as Sent for a day taken on the site by
    /// hand), in the classroom share, so the assistants see it; then today's
    /// reminder is withdrawn.
    func recordFrontDeskSend(confirmedByHand: Bool) {
        if sendsToParentLocker, let refusal = Self.parentLockerMarkRefusal(
            on: date, allowsSaving: ParentLockerSavePolicy.current.allowsSaving
        ) {
            onToast(refusal)
            return
        }
        AttendanceEmailLog.recordSend(
            on: date, role: CDClassroomMembership.currentRole(in: viewContext),
            channel: sendsToParentLocker ? .parentLocker : .email,
            confirmedByHand: confirmedByHand, in: viewContext
        )
        saveCoordinator.save(viewContext, reason: "Record front-desk email")
        frontDeskSend = AttendanceEmailLog.latestSend(on: date, in: viewContext)
        let context = viewContext
        Task { await FrontDeskEmailReminder.reschedule(in: context) }
    }

    /// Why Mark as Sent can't record `day` as sent to ParentLocker, or nil
    /// when it can. A day that hasn't come: its send would make it "after"
    /// from midnight, so its live updates would start before arrival closed
    /// (bug check 2026-10-13, C2); the email's Mark as Sent is unchanged. And
    /// a test copy: on the live store its record would silence the 9:00
    /// reminder and start every Release device's live updates
    /// (`ParentLockerSavePolicy`).
    static func parentLockerMarkRefusal(on day: Date, now: Date = Date(), allowsSaving: Bool) -> String? {
        if AppCalendar.startOfDay(day) > AppCalendar.startOfDay(now) {
            return "That day hasn't come yet. Its attendance can go to ParentLocker on the day."
        }
        if !allowsSaving { return "This test copy of the app doesn't record ParentLocker sends." }
        return nil
    }

    /// The children with `status`, as the email lists them: a child who
    /// arrived late and then left is under Left Early, "(arrived late)", as
    /// in the Daybook Assistant's email.
    func emailStudents(for status: AttendanceStatus) -> [AttendanceEmailStudent] {
        guard status == .leftEarly else { return students(for: status) }
        let cameLate = AttendanceEmailStudent.lateThenLeftEarly(on: date, in: viewContext)
        return viewModel.rows.filter { $0.status == .leftEarly }.map { row in
            AttendanceEmailStudent(row.student, arrivedLate: cameLate.contains(row.id.uuidString))
        }
    }

    func prepareAttendanceEmail() {
        let present = emailStudents(for: .present)
        let tardy = emailStudents(for: .tardy)
        let absent = emailStudents(for: .absent)
        let leftEarly = emailStudents(for: .leftEarly)
#if os(iOS)
        if MFMailComposeViewController.canSendMail() {
            showMailSheet = true
        } else if let url = AttendanceEmail.makeMailtoURL(
            to: AttendanceEmail.parseRecipients(from: AttendanceEmail.storedToAddress()),
            subject: AttendanceEmail.makeSubject(for: date),
            body: AttendanceEmail.makeBody(
                present: present, tardy: tardy, absent: absent, leftEarly: leftEarly, date: date
            )
        ) {
            // Another Mail app can't say whether it sent; ask only if one opened.
            UIApplication.shared.open(url) { accepted in
                if accepted { askingWhetherSent = true } else { onToast("No email app is set up on this device") }
            }
        }
#else
        AttendanceEmail.sendUsingMailAppForCurrentPrefs(
            present: present,
            tardy: tardy,
            absent: absent,
            leftEarly: leftEarly,
            date: date
        ) { success in
            if success {
                onToast("Email sent")
                recordFrontDeskSend(confirmedByHand: false)
            } else {
                askingWhetherSent = true
            }
        }
#endif
    }

    /// The "did it go?" question and the reminder's tap, which opens today's
    /// email unless it has gone since, or with ParentLocker picked offers to
    /// send it there. The day's send is read from the store: the tap can
    /// come as the roll appears, before it has loaded.
    var frontDeskFollowUps: FrontDeskFollowUps {
        FrontDeskFollowUps(
            askingWhetherSent: $askingWhetherSent,
            confirmingRestAbsent: $confirmingRestAbsent,
            unmarkedNames: viewModel.unmarkedNames,
            onMarkRestAbsent: markRestAbsentAndEmail,
            onSent: { recordFrontDeskSend(confirmedByHand: true) },
            onReminderTap: { asker in
                guard FrontDeskEmailReminder.isEmailRequested, Calendar.current.isDateInToday(date) else { return }
                FrontDeskEmailReminder.isEmailRequested = false
                let open = !isNonSchoolDay && AttendanceEmailLog.latestSend(on: date, in: viewContext) == nil
                switch Self.reminderTap(
                    sendsToParentLocker: sendsToParentLocker, parentLockerIsOpen: open, emailIsOpen: emailIsOn && open
                ) {
                case .offerParentLocker: offerParentLockerSend(asking: asker)
                case .openEmail: prepareAttendanceEmail()
                case .nothing: break
                }
            }
        )
    }
}

/// The attendance screen's follow-ups to the front-desk email, as a modifier
/// so its body stays one line there.
struct FrontDeskFollowUps: ViewModifier {
    @Binding var askingWhetherSent: Bool
    @Binding var confirmingRestAbsent: Bool
    let unmarkedNames: [String]
    let onMarkRestAbsent: () -> Void
    let onSent: () -> Void
    /// Handed the roll's ParentLocker asker, which `ParentLockerFollowUps`
    /// (outside this one) puts in the environment.
    let onReminderTap: (ParentLockerSendAsker?) -> Void

    @Environment(ParentLockerSendAsker.self) private var asker: ParentLockerSendAsker?

    func body(content: Content) -> some View {
        content
            .alert("Did the email go?", isPresented: $askingWhetherSent) {
                Button("It Went", action: onSent)
                Button("Not Yet", role: .cancel) {}
            } message: {
                Text("Mail didn't say. If it went, your assistants will see that the front desk has it.")
            }
            .alert(restAbsentTitle, isPresented: $confirmingRestAbsent) {
                Button("Mark \(unmarkedNames.count) Absent & Email", role: .destructive, action: onMarkRestAbsent)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(unmarkedNames.formatted(.list(type: .and))). The front desk gets the email with them absent.")
            }
            .onReceive(NotificationCenter.default.publisher(for: .frontDeskEmailRequested)) { _ in
                onReminderTap(asker)
            }
            .onAppear { onReminderTap(asker) }
    }

    private var restAbsentTitle: String {
        unmarkedNames.count == 1 ? "Mark 1 child absent?" : "Mark \(unmarkedNames.count) children absent?"
    }
}
