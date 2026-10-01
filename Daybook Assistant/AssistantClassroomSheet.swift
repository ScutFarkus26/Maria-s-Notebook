import SwiftUI
import CloudKit
import CoreData
import UserNotifications

/// The Assistant's one settings screen, behind the person button: whose
/// classroom this is and since when, what the tiles mean, which way the grid
/// runs, her name, the arrival, front-desk email and early-pickup reminders,
/// the background, the bells, and the way out.
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
    @AppStorage(EarlyPickupReminder.enabledKey) private var pickupOn = true
    @State private var notificationsDenied = false
    @AppStorage(AttendanceBells.enabledKey) private var bellsOn = false
    @AppStorage(AssistantGridOrder.key) private var gridOrderRaw = AssistantGridOrder.across.rawValue
    @AppStorage(AssistantWallpaper.key) private var wallpaperRaw = AssistantWallpaper.standard.rawValue

    var body: some View {
        NavigationStack {
            Form {
                classroomSection
                keySection
                orderSection
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
                Text("This takes the class off this iPhone. The attendance you've taken stays with your guide. "
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
                Text("If something looks wrong, read this ID to your guide. "
                    + "It tells them which class this iPhone is in.")
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
            Text("Your guide sees this name next to each child you mark.")
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
            Text("The color or photo behind the children's names. It only changes this iPhone.")
        }
    }

    private var bellsSection: some View {
        Section {
            Toggle("Bells", isOn: $bellsOn)
        } footer: {
            Text("Plays the Montessori bells as you mark. Each child you mark here rings the next note "
                + "up the scale, then back down. An absence plays a soft low C. When every child is marked, "
                + "the bells run up the whole scale. Silent mode turns them off.")
        }
        .onChange(of: bellsOn) { _, isOn in
            if isOn { AttendanceBells.shared.play(.here(count: 1)) }
        }
    }

    private var reminderSection: some View {
        Section {
            Toggle("Arrival reminder", isOn: $reminderOn)
            if reminderOn {
                DatePicker(
                    "Time", selection: ArrivalReminder.timeOfDay($reminderMinutes), displayedComponents: .hourAndMinute
                )
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
            EarlyPickupReminderRows(context: bootstrapper.coreDataStack?.viewContext)
        } footer: {
            if (reminderOn || frontDeskOn || pickupOn) && notificationsDenied {
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

    /// Says what will actually happen with the switches as they are now.
    private var reminderFooter: String {
        var lines: [String] = []
        if reminderOn {
            let at = FrontDeskEmailReminder.timeString(reminderMinutes)
            lines.append("On school days at \(at), you'll get a reminder to close arrival. "
                + "If every child is already marked, it stays quiet.")
        }
        if let dueAt = frontDeskDueAt {
            if frontDeskOn {
                lines.append("The front desk needs attendance emailed by \(dueAt). If no one has sent it yet, "
                    + "you'll get a reminder \(frontDeskLead) minutes before, and another at \(dueAt).")
            } else {
                lines.append("The front desk needs attendance emailed by \(dueAt).")
            }
        }
        if pickupOn {
            lines.append("When someone is being picked up early, you'll get a reminder before their time. "
                + "Hold a child's name and choose Leaving Early… to set it.")
        }
        return lines.isEmpty ? "Turn on a reminder to get a nudge on school days." : lines.joined(separator: " ")
    }

    /// The guide's due time ("9:00 AM"), once the guide has set up the
    /// front-desk email in the notebook.
    private var frontDeskDueAt: String? {
        guard let context = bootstrapper.coreDataStack?.viewContext,
              let settings = AttendanceEmailLog.settings(in: context), settings.canSend else { return nil }
        return FrontDeskEmailReminder.timeString(settings.deadlineMinutes)
    }

    private var frontDeskIsSetUp: Bool { frontDeskDueAt != nil }

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
            Text("This is a sample class with made-up names. Your marks stay on this iPhone "
                + "for today and go nowhere else. To take real attendance, open your guide's invitation.")
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

    /// The pinned share zone's short ID, e.g. "DB5879EF".
    private var classroomID: String? {
        guard let context = bootstrapper.coreDataStack?.viewContext,
              let zone = CDClassroomMembership.pinnedZoneName(in: context) else { return nil }
        return CDClassroomMembership.classroomID(forZone: zone)
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

// MARK: - The grid

extension AssistantClassroomSheet {

    var keySection: some View {
        Section {
            NavigationLink("What the Tiles Mean") { AssistantTileKey() }
        } footer: {
            Text("What the colors and small symbols on each child's tile mean.")
        }
    }

    var orderSection: some View {
        Section {
            Picker("Name order", selection: $gridOrderRaw) {
                ForEach(AssistantGridOrder.allCases) { order in
                    Text(order.title).tag(order.rawValue)
                }
            }
        } footer: {
            Text(AssistantGridOrder.resolved(gridOrderRaw) == .across
                ? "Names go A to Z across each row, then on to the next row. It only changes this iPhone."
                : "Names go A to Z down each column, then on to the next column. It only changes this iPhone.")
        }
    }
}
