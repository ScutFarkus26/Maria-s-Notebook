import SwiftUI
import CloudKit
import CoreData
import UserNotifications

/// The Assistant's one settings screen, behind the person button: whose
/// classroom this is and since when, her name, the arrival and front-desk
/// email reminders, the background, the bells, and the way out.
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
    @AppStorage(FrontDeskEmailReminder.enabledKey) private var frontDeskOn = FrontDeskEmailReminder.isOnByDefault
    @AppStorage(FrontDeskEmailReminder.leadKey) private var frontDeskLead = FrontDeskEmailReminder.defaultLeadMinutes
    @State private var notificationsDenied = false
    @AppStorage(AttendanceBells.enabledKey) private var bellsOn = false
    @AppStorage(AssistantWallpaper.key) private var wallpaperRaw = AssistantWallpaper.standard.rawValue

    var body: some View {
        NavigationStack {
            Form {
                classroomSection
                nameSection
                reminderSection
                backgroundSection
                bellsSection
                if AssistantSampleClass.isChosen {
                    sampleSection
                } else if bootstrapper.sharingService != nil, !AssistantSampleClass.isActive {
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

    private var backgroundSection: some View {
        Section {
            NavigationLink {
                AssistantWallpaperPicker()
            } label: {
                let wallpaper = AssistantWallpaper.resolved(wallpaperRaw)
                LabeledContent("Background") {
                    HStack(spacing: 8) {
                        Text(wallpaper.title)
                        Color.clear
                            .frame(width: 22, height: 22)
                            .background {
                                AssistantBackdrop(isToday: true, isLate: false, hereFraction: 0.6, wallpaper: wallpaper)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                            }
                            .accessibilityHidden(true)
                    }
                }
            }
        } footer: {
            Text("What's behind the class. Only on this iPhone.")
        }
    }

    private var bellsSection: some View {
        Section {
            Toggle("Bells", isOn: $bellsOn)
        } footer: {
            Text("The Montessori bells as you mark: each child here rings the next bell up the scale "
                + "and back down, an absence is the low C damped, and everyone marked runs up the scale. "
                + "The ringer switch silences them.")
        }
        .onChange(of: bellsOn) { _, isOn in
            if isOn { AttendanceBells.shared.play(.here(count: 1)) }
        }
    }

    private var reminderSection: some View {
        Section {
            Toggle("Arrival reminder", isOn: $reminderOn)
            if reminderOn {
                DatePicker("Time", selection: time($reminderMinutes), displayedComponents: .hourAndMinute)
            }
            if let dueAt = frontDeskDueAt {
                Toggle("Front desk email reminder", isOn: $frontDeskOn)
                if frontDeskOn {
                    Picker("Remind me", selection: $frontDeskLead) {
                        ForEach(FrontDeskEmailReminder.leadChoices, id: \.self) { minutes in
                            Text("\(minutes) min before \(dueAt)").tag(minutes)
                        }
                    }
                }
            }
        } footer: {
            if (reminderOn || frontDeskOn) && notificationsDenied {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notifications are off for Daybook Assistant.")
                    Button("Turn On in Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            } else {
                Text(reminderFooter)
            }
        }
        .task(id: "\(reminderOn)|\(reminderMinutes)|\(frontDeskOn)|\(frontDeskLead)") {
            await applyReminderSetting()
        }
    }

    private var reminderFooter: String {
        let arrival = "On school days, a reminder to close arrival, unless everyone's already marked."
        guard let dueAt = frontDeskDueAt else { return arrival }
        return arrival + " The front desk needs attendance by \(dueAt): that one comes before then, "
            + "and again at \(dueAt), if nobody has emailed it yet."
    }

    /// The guide's due time ("9:00 AM"), once the guide has set up the
    /// front-desk email in the notebook.
    private var frontDeskDueAt: String? {
        guard let context = bootstrapper.coreDataStack?.viewContext,
              let settings = AttendanceEmailLog.settings(in: context), settings.canSend else { return nil }
        return FrontDeskEmailReminder.timeString(settings.deadlineMinutes)
    }

    private var frontDeskIsSetUp: Bool { frontDeskDueAt != nil }

    /// Minutes after midnight, as the time the picker shows.
    private func time(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                let midnight = Calendar.current.startOfDay(for: Date())
                return Calendar.current.date(byAdding: .minute, value: minutes.wrappedValue, to: midnight) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (parts.hour ?? 8) * 60 + (parts.minute ?? 15)
            }
        )
    }

    private func applyReminderSetting() async {
        // The sample class schedules nothing, so it doesn't ask either.
        if AssistantSampleClass.isActive { return }
        if reminderOn { await ArrivalReminder.requestPermissionIfNeeded() }
        if frontDeskOn, frontDeskIsSetUp { _ = await FrontDeskEmailReminder.requestPermission() }
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notificationsDenied = status == .denied
        if let context = bootstrapper.coreDataStack?.viewContext {
            await ArrivalReminder.reschedule(in: context)
            await FrontDeskEmailReminder.reschedule(in: context)
        }
    }

    /// The sample class opened from the join screen: the way back to joining.
    private var sampleSection: some View {
        Section {
            Button("Leave Sample Class") {
                dismiss()
                bootstrapper.leaveSampleClass()
            }
        } footer: {
            Text("This is a sample class with made-up names. Nothing you mark here is saved. "
                + "To take real attendance, open your guide's invitation.")
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
