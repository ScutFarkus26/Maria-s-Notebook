import CoreData
import Foundation
import SwiftUI

// MARK: - Settings View

/// Settings › Messages › Attendance to the School: how the day's attendance
/// goes (ParentLocker, or the front-desk email), that method's settings, and
/// the due time with this device's reminder.
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
    @SyncedAppStorage(AttendanceEmailPrefs.deadlineKey)
    private var deadlineMinutes: Int = AttendanceEmailLog.defaultDeadlineMinutes
    // Shared with the assistants, as the email's settings are (schema 18).
    @SyncedAppStorage(AttendanceEmailPrefs.sendMethodKey)
    private var sendMethodRaw: String = AttendanceSendMethod.email.rawValue
    @SyncedAppStorage(AttendanceEmailPrefs.parentLockerSiteKey) private var parentLockerSite: String = ""
    @State private var notificationsDenied = false
    /// The settings as last seen here: what the screen opened with, then each edit.
    @State private var seenSignature: String?
    /// The method as last seen here; a new one reaches the share at once.
    @State private var seenMethod: String?
    /// Something was edited on this screen, so closing it writes the share
    /// again (an untouched screen writes nothing; see `applyChanges`).
    @State private var editedHere = false
    @Environment(\.managedObjectContext) private var viewContext

    public init() {}

    /// SyncedAppStorage stores primitives, so the picker reads and writes the raw value.
    private var nameOrder: Binding<AttendanceEmailNameOrder> {
        Binding(
            get: { AttendanceEmailNameOrder(rawValue: nameOrderRaw) ?? .firstLast },
            set: { nameOrderRaw = $0.rawValue }
        )
    }

    private var sendMethod: Binding<AttendanceSendMethod> {
        Binding(
            get: { AttendanceSendMethod(stored: sendMethodRaw) },
            set: { sendMethodRaw = $0.rawValue }
        )
    }

    private var sendsToParentLocker: Bool { sendMethod.wrappedValue == .parentLocker }

    private var methodPicker: some View {
        LabeledContent("Send attendance by") {
            Picker("Send attendance by", selection: sendMethod) {
                Text("ParentLocker").tag(AttendanceSendMethod.parentLocker)
                Text("Email to the front desk").tag(AttendanceSendMethod.email)
            }
            .labelsHidden()
            .fixedSize()
        }
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
            DatePicker(
                sendsToParentLocker ? "Due in ParentLocker by" : "Due at the front desk by",
                selection: deadlineTime, displayedComponents: .hourAndMinute
            )
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
                let midnight = Calendar.current.startOfDay(for: Date())
                return Calendar.current.date(byAdding: .minute, value: deadlineMinutes, to: midnight) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                deadlineMinutes = (parts.hour ?? 9) * 60 + (parts.minute ?? 0)
            }
        )
    }

    /// Carries the settings to the assistants (after typing pauses, not per
    /// keystroke: each write is a CloudKit upload) and rebuilds the reminder.
    private func applyChanges() async {
        // Only an edit writes. The screen opening, or reappearing with its
        // state kept (a Mac Settings pane), runs this too with the settings
        // unchanged; this device's stored settings may be behind an edit made
        // on another of the guide's devices, so those write nothing (2026-10-05).
        let signature = changeSignature
        guard let seen = seenSignature, seen != signature else {
            seenSignature = signature
            seenMethod = sendMethodRaw
            return
        }
        seenSignature = signature
        editedHere = true
        // A new method reaches the share now, not after the pause: the roll,
        // the sync, the reminder, MCP and the assistants all read it there,
        // and a pause cut short by closing Settings left them on the old one
        // (bug check 2026-10-13, C1). The site waits for typing to pause (or
        // Return, or closing): each half-typed host would sign this device out.
        if seenMethod != sendMethodRaw {
            seenMethod = sendMethodRaw
            Self.shareNow(in: viewContext)
        }
        guard (try? await Task.sleep(for: .seconds(1.5))) != nil else { return }
        Self.shareAndRefresh(in: viewContext)
        if reminderOn { notificationsDenied = !(await FrontDeskEmailReminder.requestPermission()) }
        await FrontDeskEmailReminder.reschedule(in: viewContext)
    }

    private var changeSignature: String {
        "\(enabled)|\(toAddress)|\(nameOrderRaw)|\(groupByLevel)|\(deadlineMinutes)|\(reminderOn)|\(reminderLead)"
            + "|\(sendMethodRaw)|\(parentLockerSite)"
    }

    public var body: some View {
        platformBody
            .task(id: changeSignature) { await applyChanges() }
            // A method or site that never reached the share (bug check
            // 2026-10-13 review, C1): put right as Settings opens.
            .onAppear { Self.repairSharedMethodNow(in: viewContext) }
            // Closing Settings cancels the pause above: an edit made here
            // goes into the share as the screen closes.
            .onDisappear {
                guard editedHere else { return }
                editedHere = false
                Self.shareNow(in: viewContext)
            }
    }

    /// Says which of the typed entries aren't addresses, and get no email.
    @ViewBuilder
    private var leftOutNote: some View {
        if let note = AttendanceEmail.leftOutNote(for: toAddress) {
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
                AttendanceParentLockerSettings(site: $parentLockerSite) {
                    editedHere = false
                    Self.shareNow(in: viewContext)
                }
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
                Toggle("Enabled", isOn: $enabled)
                    .labelsHidden()
            }
            LabeledContent("Send to") {
                TextField("Email addresses", text: $toAddress)
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
                Toggle("Group by level", isOn: $groupByLevel)
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
            Toggle("Show the attendance email button", isOn: $enabled)

            TextField("Send To", text: $toAddress)
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
            Toggle("Group by Level", isOn: $groupByLevel)
            groupingFootnote

            Divider()

            Text("Front Desk Deadline")
                .font(.subheadline.weight(.semibold))
            reminderRows
        }
        #endif
    }
}

extension AttendanceEmailSettingsView {

    /// Writes the settings into the share and saves, now, then brings this
    /// device's ParentLocker sign-in and line (a new site or method) and the
    /// reminder up to date with them. The reminder's rebuild runs in a task
    /// of its own, which finishes even when Settings has closed.
    static func shareNow(in context: NSManagedObjectContext) {
        shareAndRefresh(in: context)
        Task { await FrontDeskEmailReminder.reschedule(in: context) }
    }

    /// `shareNow` without the reminder, for the pause's write, which asks
    /// for notifications before it rebuilds the reminder.
    static func shareAndRefresh(in context: NSManagedObjectContext) {
        shareSettingsNow(in: context)
        if let sync = ParentLockerSync.current(for: context) {
            sync.refreshSignIn()
            sync.refreshStatus()
        }
    }

    /// The share's method and site put right from this device's preferences,
    /// saved, and this device's ParentLocker line with them
    /// (`AttendanceEmail.repairSharedMethod`). Returns whether anything was written.
    @discardableResult
    static func repairSharedMethodNow(
        in context: NSManagedObjectContext,
        settings: AttendanceEmailLog.Settings = AttendanceEmail.storedSettings(),
        firstDownloadPending: Bool = FirstDownloadGate.isPending()
    ) -> Bool {
        guard AttendanceEmail.repairSharedMethod(
            in: context, settings: settings, firstDownloadPending: firstDownloadPending
        ), context.safeSave() else { return false }
        if let sync = ParentLockerSync.current(for: context) {
            sync.refreshSignIn()
            sync.refreshStatus()
        }
        return true
    }

    /// The guide's settings into the share, saved (`AttendanceEmail.shareSettings`:
    /// the lead guide's devices only, and not during a first download).
    /// Returns whether anything was written.
    @discardableResult
    static func shareSettingsNow(
        in context: NSManagedObjectContext,
        settings: AttendanceEmailLog.Settings = AttendanceEmail.storedSettings(),
        firstDownloadPending: Bool = FirstDownloadGate.isPending()
    ) -> Bool {
        guard AttendanceEmail.shareSettings(
            in: context, settings: settings, firstDownloadPending: firstDownloadPending
        ) else { return false }
        return context.safeSave()
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
