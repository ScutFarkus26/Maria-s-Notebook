import SwiftUI
import CloudKit
import CoreData
import UserNotifications

/// The Assistant's one settings screen, behind the person button: whose
/// classroom this is and since when, her name, the arrival reminder, the
/// bells, and the way out.
///
/// The guide's name comes from the share's owner identity at display time.
/// Apple's terms allow showing it to participants but never storing it, and
/// iOS 26+ hands it over only with the extended-share-access entitlement;
/// without either it reads "Your guide".
struct AssistantClassroomSheet: View {
    @Environment(AssistantBootstrapper.self) private var bootstrapper
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ClassroomIdentity.displayName
    @State private var showingNameSheet = false
    @State private var confirmingLeave = false
    @State private var isLeaving = false
    @State private var leaveError: String?
    @AppStorage(ArrivalReminder.enabledKey) private var reminderOn = true
    @AppStorage(ArrivalReminder.timeKey) private var reminderMinutes = ArrivalReminder.defaultMinutes
    @State private var notificationsDenied = false
    @AppStorage(AssistantBells.enabledKey) private var bellsOn = false

    var body: some View {
        NavigationStack {
            Form {
                classroomSection
                nameSection
                reminderSection
                bellsSection
                if bootstrapper.sharingService != nil {
                    leaveSection
                }
            }
            .navigationTitle("Classroom")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(
                isPresented: $showingNameSheet,
                onDismiss: { displayName = ClassroomIdentity.displayName },
                content: { AssistantNameSheet() }
            )
            .confirmationDialog(
                "Leave this classroom?",
                isPresented: $confirmingLeave,
                titleVisibility: .visible
            ) {
                Button("Leave Classroom", role: .destructive) {
                    Task { await leave() }
                }
            } message: {
                Text("The class is removed from this iPhone. The attendance you took stays with your guide. "
                    + "To come back, open your guide's invitation again.")
            }
        }
    }

    // MARK: - Sections

    private var classroomSection: some View {
        Section {
            LabeledContent("Guide", value: guideName)
            if let joined {
                LabeledContent("Joined", value: joined.formatted(date: .abbreviated, time: .omitted))
            }
            if let classroomID {
                LabeledContent("Classroom ID") {
                    Text(classroomID)
                        .monospaced()
                        .textSelection(.enabled)
                }
            }
        } header: {
            Text("Classroom")
        } footer: {
            if classroomID != nil {
                Text("If something looks wrong, the classroom ID tells your guide which class this iPhone is in.")
            }
        }
    }

    private var nameSection: some View {
        Section {
            Button {
                showingNameSheet = true
            } label: {
                LabeledContent("Your name", value: displayName ?? "Not set")
            }
            .foregroundStyle(.primary)
        } footer: {
            Text("Shown beside the attendance you take.")
        }
    }

    private var bellsSection: some View {
        Section {
            Toggle("Bells", isOn: $bellsOn)
        } footer: {
            Text("A soft bell as you mark each child, climbing as the class fills, and a little tune when "
                + "everyone's marked. The ringer switch silences them.")
        }
        .onChange(of: bellsOn) { _, isOn in
            if isOn { AssistantBells.shared.play(.here(count: 1)) }
        }
    }

    private var reminderSection: some View {
        Section {
            Toggle("Arrival reminder", isOn: $reminderOn)
            if reminderOn {
                DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
            }
        } footer: {
            if reminderOn && notificationsDenied {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notifications are off for Daybook Assistant.")
                    Button("Turn On in Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            } else {
                Text("On school days, a reminder to switch to Late, unless everyone's already marked.")
            }
        }
        .task(id: "\(reminderOn)|\(reminderMinutes)") {
            await applyReminderSetting()
        }
    }

    /// Minutes after midnight, as the time the picker shows.
    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                let midnight = Calendar.current.startOfDay(for: Date())
                return Calendar.current.date(byAdding: .minute, value: reminderMinutes, to: midnight) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                reminderMinutes = (parts.hour ?? 8) * 60 + (parts.minute ?? 15)
            }
        )
    }

    private func applyReminderSetting() async {
        if reminderOn { await ArrivalReminder.requestPermissionIfNeeded() }
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notificationsDenied = status == .denied
        #if DEBUG
        if AssistantSampleClass.isRequested { return }
        #endif
        if let context = bootstrapper.coreDataStack?.viewContext {
            await ArrivalReminder.reschedule(in: context)
        }
    }

    private var leaveSection: some View {
        Section {
            Button("Leave Classroom", role: .destructive) {
                confirmingLeave = true
            }
            .disabled(isLeaving)
        } footer: {
            if let leaveError {
                Text(leaveError).foregroundStyle(.red)
            }
        }
    }

    // MARK: - Values

    private var guideName: String { bootstrapper.guideName ?? "Your guide" }

    private var joined: Date? {
        guard let context = bootstrapper.coreDataStack?.viewContext else { return nil }
        return CDClassroomMembership.current(in: context)?.joinedAt
    }

    /// The first 8 characters of the pinned share zone, e.g. "DB5879EF".
    private var classroomID: String? {
        guard let context = bootstrapper.coreDataStack?.viewContext,
              let zone = CDClassroomMembership.pinnedZoneName(in: context) else { return nil }
        return String(zone.prefix(8))
    }

    private func leave() async {
        isLeaving = true
        leaveError = nil
        do {
            try await bootstrapper.leaveClassroom()
            dismiss()
        } catch {
            // CloudKit's own text reads as jargon; the purge only fails on
            // reaching iCloud, and the class stays until it succeeds.
            leaveError = "Couldn't leave the classroom. Check that this iPhone is online, then try again."
        }
        isLeaving = false
    }
}
