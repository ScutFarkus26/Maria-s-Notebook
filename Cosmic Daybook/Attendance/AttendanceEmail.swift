import Foundation
import SwiftUI
import OSLog

#if os(macOS)
import AppKit
import ObjectiveC
#endif

// MARK: - Settings View

/// Settings form for configuring Attendance Email behavior.
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
    @State private var notificationsDenied = false
    @Environment(\.managedObjectContext) private var viewContext

    public init() {}

    /// SyncedAppStorage stores primitives, so the picker reads and writes the raw value.
    private var nameOrder: Binding<AttendanceEmailNameOrder> {
        Binding(
            get: { AttendanceEmailNameOrder(rawValue: nameOrderRaw) ?? .firstLast },
            set: { nameOrderRaw = $0.rawValue }
        )
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
            DatePicker("Due at the front desk by", selection: deadlineTime, displayedComponents: .hourAndMinute)
            Toggle("Remind me if it hasn't gone", isOn: $reminderOn)
            if reminderOn {
                Picker("Remind me", selection: $reminderLead) {
                    ForEach(FrontDeskEmailReminder.leadChoices, id: \.self) { minutes in
                        Text("\(minutes) minutes before").tag(minutes)
                    }
                }
            }
            Text(notificationsDenied && reminderOn
                ? "Notifications are off for Cosmic Daybook, so the reminder can't show."
                : "The due time and these settings go to your assistants' Daybook Assistant, which sends the "
                    + "same email to the same addresses. The reminder is this device's own: on school days, "
                    + "before the due time and again at it, if nobody has sent the day's email.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
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
        guard (try? await Task.sleep(for: .seconds(1.5))) != nil else { return }
        if AttendanceEmail.shareSettings(in: viewContext) { viewContext.safeSave() }
        if reminderOn { notificationsDenied = !(await FrontDeskEmailReminder.requestPermission()) }
        await FrontDeskEmailReminder.reschedule(in: viewContext)
    }

    private var changeSignature: String {
        "\(enabled)|\(toAddress)|\(nameOrderRaw)|\(groupByLevel)|\(deadlineMinutes)|\(reminderOn)|\(reminderLead)"
    }

    public var body: some View {
        platformBody
            .task(id: changeSignature) { await applyChanges() }
            .onChange(of: enabled) { _, _ in SettingsCategory.markModified(.communication) }
            .onChange(of: toAddress) { _, _ in SettingsCategory.markModified(.communication) }
            .onChange(of: fromAddress) { _, _ in SettingsCategory.markModified(.communication) }
            .onChange(of: nameOrderRaw) { _, _ in SettingsCategory.markModified(.communication) }
            .onChange(of: groupByLevel) { _, _ in SettingsCategory.markModified(.communication) }
            .onChange(of: deadlineMinutes) { _, _ in SettingsCategory.markModified(.communication) }
    }

    @ViewBuilder
    private var platformBody: some View {
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
            Text("You can enter multiple addresses separated by commas or semicolons.")
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
            Toggle("Show 'Send Attendance Email' Button", isOn: $enabled)

            TextField("Send To", text: $toAddress)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                #endif

            #if os(iOS)
            TextField("Preferred 'From' Address (iOS)", text: $fromAddress)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            #else
            TextField("Preferred 'From' Address (iOS only)", text: $fromAddress)
                .textFieldStyle(.roundedBorder)
                .disabled(true)
                .foregroundStyle(.secondary)
            #endif

            Text("Note: iOS uses the preferred address when possible. macOS uses your default Mail account.")
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

// MARK: - macOS Mail Sender Helper

#if os(macOS)
public enum MacOSMailSender {
    private static let logger = Logger.attendance
    public static func send(
        to recipient: String?,
        subject: String,
        body: String,
        attachmentURL: URL? = nil,
        completion: @escaping (Bool) -> Void
    ) {
        guard let service = NSSharingService(named: .composeEmail) else {
            Task {
                completion(false)
            }
            return
        }
        if let r = recipient {
            let recipients = AttendanceEmail.parseRecipients(from: r)
            if !recipients.isEmpty {
                service.recipients = recipients
            }
        }
        service.subject = subject
        
        // Timeout fallback: ensure completion is called even if delegate callbacks don't fire
        var hasCompleted = false
        let timeoutTask = Task {
            do {
                try await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
            } catch {
                logger.warning("Task sleep interrupted: \(error)")
            }
            if !hasCompleted {
                hasCompleted = true
                completion(false) // Timeout treated as failure
            }
        }
        
        let delegate = SharingDelegate { success in
            Task {
                if !hasCompleted {
                    hasCompleted = true
                    timeoutTask.cancel()
                    completion(success)
                }
            }
        }
        service.delegate = delegate
        // Keep the delegate alive until completion by retaining it on the service via associated object.
        objc_setAssociatedObject(
            service,
            Unmanaged.passUnretained(delegate).toOpaque(),
            delegate,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        var items: [Any] = [body]
        if let attachmentURL {
            items.append(attachmentURL)
        }
        service.perform(withItems: items)
    }

    private final class SharingDelegate: NSObject, NSSharingServiceDelegate {
        private let completion: (Bool) -> Void
        init(completion: @escaping (Bool) -> Void) { self.completion = completion }

        func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
            completion(true)
            clearAssociation(from: sharingService)
        }
        func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
            completion(false)
            clearAssociation(from: sharingService)
        }
        private func clearAssociation(from service: NSSharingService) {
            objc_removeAssociatedObjects(service)
        }
    }
}
#endif
