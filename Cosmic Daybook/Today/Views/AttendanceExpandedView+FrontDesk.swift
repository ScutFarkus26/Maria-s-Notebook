// AttendanceExpandedView+FrontDesk.swift
// The front-desk attendance email: sending it, recording that it went, and
// the reminder's tap.

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
    var deadlineMinutes: Int { AttendanceEmail.storedSettings().deadlineMinutes }

    /// The two moments the control changes: half an hour before the due
    /// time, and at it. A timeline redraws it then and at no other time.
    private var frontDeskChangeTimes: [Date] {
        let calendar = Calendar.current
        guard let deadline = calendar.date(
            byAdding: .minute, value: deadlineMinutes, to: calendar.startOfDay(for: date)
        ) else { return [] }
        return [deadline.addingTimeInterval(-Double(AttendanceEmailLog.dueWindowMinutes) * 60), deadline]
    }

    var frontDeskControl: some View {
        // The clock is read, not the entry's date: before the first entry an
        // explicit timeline hands the view that first entry, not now.
        TimelineView(.explicit(frontDeskChangeTimes)) { _ in
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
    @ViewBuilder
    var compactFrontDeskRow: some View {
        #if os(iOS)
        let near = AttendanceEmailLog.urgency(for: date, deadlineMinutes: deadlineMinutes) != .none
        if hSizeClass == .compact, emailEnabled, !isNonSchoolDay, frontDeskSend != nil || isRollComplete || near {
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

    /// Who sent the day's email, as this screen reads it ("you" for the
    /// guide's own).
    func frontDeskSummary(_ send: AttendanceEmailLog.Send) -> String {
        let name = send.senderName(
            viewerRole: CDClassroomMembership.currentRole(in: viewContext),
            myRecordName: ClassroomIdentity.currentUserRecordName,
            myName: ClassroomIdentity.displayName
        )
        return send.summary(senderName: name, for: date, deadlineMinutes: deadlineMinutes)
    }

    /// Records that the day's email went, in the classroom share, so the
    /// assistants see it; then today's reminder is withdrawn.
    func recordFrontDeskSend(confirmedByHand: Bool) {
        AttendanceEmailLog.recordSend(
            on: date, role: CDClassroomMembership.currentRole(in: viewContext),
            confirmedByHand: confirmedByHand, in: viewContext
        )
        saveCoordinator.save(viewContext, reason: "Record front-desk email")
        frontDeskSend = AttendanceEmailLog.latestSend(on: date, in: viewContext)
        let context = viewContext
        Task { await FrontDeskEmailReminder.reschedule(in: context) }
    }

    func prepareAttendanceEmail() {
        let present = students(for: .present)
        let tardy = students(for: .tardy)
        let absent = students(for: .absent)
        let leftEarly = students(for: .leftEarly)
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
    /// email unless it has gone since.
    var frontDeskFollowUps: FrontDeskFollowUps {
        FrontDeskFollowUps(
            askingWhetherSent: $askingWhetherSent,
            confirmingRestAbsent: $confirmingRestAbsent,
            unmarkedNames: viewModel.unmarkedNames,
            onMarkRestAbsent: markRestAbsentAndEmail,
            onSent: { recordFrontDeskSend(confirmedByHand: true) },
            onReminderTap: {
                guard FrontDeskEmailReminder.isEmailRequested, Calendar.current.isDateInToday(date) else { return }
                FrontDeskEmailReminder.isEmailRequested = false
                if emailEnabled, !isNonSchoolDay, frontDeskSend == nil { prepareAttendanceEmail() }
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
    let onReminderTap: () -> Void

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
            .onReceive(NotificationCenter.default.publisher(for: .frontDeskEmailRequested)) { _ in onReminderTap() }
            .onAppear(perform: onReminderTap)
    }

    private var restAbsentTitle: String {
        unmarkedNames.count == 1 ? "Mark 1 child absent?" : "Mark \(unmarkedNames.count) children absent?"
    }
}
