import CoreData
import Foundation
import SwiftUI

// MARK: - Settings View

/// Settings › Messages › Attendance to the School: how the day's attendance
/// goes (ParentLocker, or the front-desk email), that method's settings, and
/// the due time with this device's reminder.
///
/// The method, the ParentLocker address and the due time show as the shared
/// settings row holds them, which is what everything else reads; the email's
/// own fields as this device's preferences hold them, which the notebook's
/// own email is written from (`AttendanceEmail.shownSettings`). Only the
/// person's own actions write, each only the field it changed
/// (`AttendanceEmail.shareEdit`), so a device whose preferences are behind
/// the share, or a change synced in while Settings is open, never switches
/// the class back to email (bug hunt 2026-10-13 afternoon, H1).
/// - CDNote: The "Preferred 'From' Address" applies to iOS only;
///   macOS always uses the default Mail account.
public struct AttendanceEmailSettingsView: View {
    @SyncedAppStorage(AttendanceEmailPrefs.enabledKey) private var enabled: Bool = true
    @SyncedAppStorage(AttendanceEmailPrefs.toKey) private var toAddress: String = ""
    @SyncedAppStorage(AttendanceEmailPrefs.fromKey) private var fromAddress: String = ""
    @SyncedAppStorage(AttendanceEmailPrefs.groupByLevelKey) private var groupByLevel: Bool = false
    @SyncedAppStorage(AttendanceEmailPrefs.nameOrderKey)
    private var nameOrderRaw: String = AttendanceEmailNameOrder.firstLast.rawValue
    // The reminder is this device's own, not synced: whoever wants it turns it on.
    @AppStorage(FrontDeskEmailReminder.enabledKey) private var reminderOn = FrontDeskEmailReminder.isOnByDefault
    @AppStorage(FrontDeskEmailReminder.leadKey) private var reminderLead = FrontDeskEmailReminder.defaultLeadMinutes
    // This device's copies of the shared choices: shown only before the
    // share has a settings row.
    @SyncedAppStorage(AttendanceEmailPrefs.deadlineKey)
    private var deadlineMinutes: Int = AttendanceEmailLog.defaultDeadlineMinutes
    @SyncedAppStorage(AttendanceEmailPrefs.sendMethodKey)
    private var sendMethodRaw: String = AttendanceSendMethod.email.rawValue
    @SyncedAppStorage(AttendanceEmailPrefs.parentLockerSiteKey) private var parentLockerSite: String = ""
    @State private var notificationsDenied = false
    /// The shared settings row as last read: as the screen opens, after each
    /// write here, and as a change arrives. Nil before the share has one,
    /// and while it holds only the launch's own (`AttendanceEmail.shownRow`).
    @State private var sharedRow: AttendanceEmailLog.Settings?
    /// What was typed here and not yet written.
    @State private var drafts = AttendanceSettingsDrafts()
    /// The pause typing waits for before `drafts.paused` is written.
    @State private var pause: Task<Void, Never>?
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.isSampleClassroom) private var isSampleClassroom

    public init() {}

    /// What the screen shows (see the type's note).
    private var shown: AttendanceEmailLog.Settings {
        AttendanceEmail.shownSettings(
            row: sharedRow,
            preferences: AttendanceEmailLog.Settings(
                isEnabled: enabled,
                toAddresses: toAddress,
                nameOrder: AttendanceEmailNameOrder(rawValue: nameOrderRaw) ?? .firstLast,
                groupByLevel: groupByLevel,
                deadlineMinutes: deadlineMinutes,
                sendMethod: AttendanceSendMethod(stored: sendMethodRaw),
                parentLockerSite: AttendanceEmailLog.parentLockerHost(parentLockerSite)
            ),
            isSampleClass: isSampleClassroom
        )
    }

    // The controls: each one's setter is an edit, and the only way one is made.

    private var sendMethod: Binding<AttendanceSendMethod> {
        Binding(get: { shown.sendMethod }, set: { share(AttendanceSettingsEdit(sendMethod: $0)) })
    }

    private var emailOn: Binding<Bool> {
        Binding(get: { shown.isEnabled }, set: { share(AttendanceSettingsEdit(isEnabled: $0)) })
    }

    private var nameOrder: Binding<AttendanceEmailNameOrder> {
        Binding(get: { shown.nameOrder }, set: { share(AttendanceSettingsEdit(nameOrder: $0)) })
    }

    private var groupsByLevel: Binding<Bool> {
        Binding(get: { shown.groupByLevel }, set: { share(AttendanceSettingsEdit(groupByLevel: $0)) })
    }

    private var recipients: Binding<String> {
        Binding(
            get: { drafts.paused.toAddresses ?? shown.toAddresses },
            set: { typed(AttendanceSettingsEdit(toAddresses: $0)) }
        )
    }

    /// The ParentLocker address: typing changes only the draft (L3).
    private var site: Binding<String> {
        Binding(get: { drafts.site ?? shown.parentLockerSite }, set: { drafts.site = $0 })
    }

    private var sendsToParentLocker: Bool { shown.sendMethod == .parentLocker }

    private var methodPicker: some View {
        AttendanceSendMethodPicker(method: sendMethod)
    }

    private var nameOrderPicker: some View {
        Picker("Name order", selection: nameOrder) {
            ForEach(AttendanceEmailNameOrder.allCases) { order in
                Text(order.title).tag(order)
            }
        }
    }

    private var groupingFootnote: some View {
        Text(
            "Grouping writes each level as its own report \u{2014} on time, tardy, "
            + "left early and absent \u{2014} Upper Elementary first."
        )
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    /// When the front desk needs it by (shared with the assistants), and this
    /// device's reminder: its switch, how long before, and why it can't show
    /// when notifications are off.
    private var reminderRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            let due = sendsToParentLocker ? "Due in ParentLocker by" : "Due at the front desk by"
            AttendanceSettingRow(due) { _ in
                DatePicker(due, selection: deadlineTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            Toggle("Remind me if it hasn't gone", isOn: $reminderOn)
            if reminderOn {
                Picker("Remind me", selection: $reminderLead) {
                    ForEach(FrontDeskEmailReminder.leadChoices, id: \.self) { minutes in
                        Text("\(minutes) minutes before").tag(minutes)
                    }
                }
            }
            Text(notificationsDenied && reminderOn
                ? "Notifications are off for Cosmic Daybook, so the reminder can't show. "
                    + "Turn them on in \(SystemSettingsApp.name) › Notifications."
                : reminderFootnote)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var reminderFootnote: String {
        sendsToParentLocker
            ? "The due time and this choice go to the Daybook Assistant app on your assistants' phones. "
                + "The reminder is this device's own: on school days, before the due time and again at it, "
                + "if nobody has sent the day's attendance to ParentLocker."
            : "The due time and these settings go to the Daybook Assistant app on your assistants' phones, "
                + "which sends the same email to the same addresses. The reminder is this device's own: "
                + "on school days, before the due time and again at it, if nobody has sent the day's email."
    }

    /// Minutes after midnight, as the time the picker shows.
    private var deadlineTime: Binding<Date> {
        Binding(
            get: {
                let minutes = drafts.paused.deadlineMinutes ?? shown.deadlineMinutes
                let midnight = Calendar.current.startOfDay(for: Date())
                return Calendar.current.date(byAdding: .minute, value: minutes, to: midnight) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                typed(AttendanceSettingsEdit(deadlineMinutes: (parts.hour ?? 9) * 60 + (parts.minute ?? 0)))
            }
        )
    }

    public var body: some View {
        platformBody
            .onAppear(perform: opened)
            // A change synced in (or made in another window) only shows
            // here: it is never taken for an edit.
            .onPresentationDataChange(of: ["AttendanceEmailSettings"], in: viewContext) { _ in
                sharedRow = AttendanceEmail.shownRow(in: viewContext, isSampleClass: isSampleClassroom)
            }
            .onChange(of: reminderOn) { reminderChanged() }
            .onChange(of: reminderLead) { reminderChanged() }
            .onDisappear(perform: closed)
    }

    /// Says which of the typed entries aren't addresses, and get no email.
    @ViewBuilder
    private var leftOutNote: some View {
        if let note = AttendanceEmail.leftOutNote(for: recipients.wrappedValue) {
            Text(note)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var platformBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            methodPicker
            Divider()
            if sendsToParentLocker {
                AttendanceParentLockerSettings(site: site, commitSite: commitSite)
                Divider()
                #if !os(macOS)
                Text("Deadline")
                    .font(.subheadline.weight(.semibold))
                #endif
                reminderRows
            } else {
                emailRows
            }
        }
    }

    /// The front-desk email's settings, then its due time and the reminder.
    @ViewBuilder
    private var emailRows: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Attendance email") {
                Toggle("Enabled", isOn: emailOn)
                    .labelsHidden()
            }
            LabeledContent("Send to") {
                TextField("Email addresses", text: recipients)
                    .frame(minWidth: 260)
            }
            leftOutNote
            LabeledContent("From account") {
                Text("Default Mail account")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Name order") {
                nameOrderPicker
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
            }
            LabeledContent("Group by level") {
                Toggle("Group by level", isOn: groupsByLevel)
                    .labelsHidden()
            }
            groupingFootnote
            Text("You can enter several addresses, separated by commas or spaces.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Divider()
            reminderRows
        }
        #else
        // A plain stack, not a Form: this view is embedded inline in a SettingsGroup
        // inside the settings ScrollView, and a nested Form scrolls its own sections
        // out of reach — which is how Report Format went missing.
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Show the attendance email button", isOn: emailOn)

            TextField("Send To", text: recipients)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                #endif
            leftOutNote

            #if os(iOS)
            TextField("Send from", text: $fromAddress)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            #else
            TextField("Send from (iPhone and iPad only)", text: $fromAddress)
                .textFieldStyle(.roundedBorder)
                .disabled(true)
                .foregroundStyle(.secondary)
            #endif

            Text("Mail sends from this address when it can. On a Mac it uses your usual Mail account.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Divider()

            Text("Report Format")
                .font(.subheadline.weight(.semibold))
            nameOrderPicker
                .pickerStyle(.segmented)
            Toggle("Group by Level", isOn: groupsByLevel)
            groupingFootnote

            Divider()

            Text("Front Desk Deadline")
                .font(.subheadline.weight(.semibold))
            reminderRows
        }
        #endif
    }
}

// MARK: - Writes

extension AttendanceEmailSettingsView {

    /// Settings opening: the shared row as it is, after a write this device
    /// put off during a first download, if it's still owed
    /// (`AttendanceEmail.writePendingEdit`). Nothing else is written here.
    private func opened() {
        if AttendanceEmail.writePendingEdit(in: viewContext, isSampleClass: isSampleClassroom) {
            Self.followShare(in: viewContext)
        }
        sharedRow = AttendanceEmail.shownRow(in: viewContext, isSampleClass: isSampleClassroom)
    }

    /// An edit made here goes into the share now (`AttendanceEmail.shareEdit`).
    private func share(_ edit: AttendanceSettingsEdit) {
        guard !edit.isEmpty else { return }
        AttendanceEmail.shareEdit(edit, in: viewContext, isSampleClass: isSampleClassroom)
        sharedRow = AttendanceEmail.shownRow(in: viewContext, isSampleClass: isSampleClassroom)
        // The Sample Class has no ParentLocker, and its row is no reason to
        // rebuild the guide's reminder.
        guard !isSampleClassroom else { return }
        Self.followShare(in: viewContext)
    }

    /// Typing in the email's addresses or picking the due time: written once
    /// it pauses, since each write is a CloudKit upload.
    private func typed(_ edit: AttendanceSettingsEdit) {
        drafts.paused = drafts.paused.merged(with: edit)
        pause?.cancel()
        pause = Task {
            guard (try? await Task.sleep(for: .seconds(1.5))) != nil else { return }
            share(drafts.takePaused())
        }
    }

    /// Return in the address field, or the sign-in sheet about to open: the
    /// typed address goes in now, so the sheet signs in to it (L3).
    private func commitSite() {
        share(drafts.takeSite(shown: shown.parentLockerSite))
    }

    /// Settings closing, which cancels the pause: what was typed here and
    /// not yet written goes in, and nothing else.
    private func closed() {
        pause?.cancel()
        pause = nil
        share(drafts.takeAll(shownSite: shown.parentLockerSite))
    }

    /// This device's reminder: its switch or how long before changed here.
    private func reminderChanged() {
        Task {
            if reminderOn { notificationsDenied = !(await FrontDeskEmailReminder.requestPermission()) }
            await FrontDeskEmailReminder.reschedule(in: viewContext)
        }
    }

    /// After the share's settings changed here: this device's ParentLocker
    /// sign-in and line (a new site or method) and the reminder follow. The
    /// reminder's rebuild runs in a task of its own, which finishes even
    /// when Settings has closed.
    static func followShare(in context: NSManagedObjectContext) {
        if let sync = ParentLockerSync.current(for: context) {
            sync.refreshSignIn()
            sync.refreshStatus()
        }
        Task { await FrontDeskEmailReminder.reschedule(in: context) }
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct AttendanceEmailPreview: View {
    var body: some View {
        AttendanceEmailSettingsView()
    }
}

#Preview {
    AttendanceEmailPreview()
}
