import SwiftUI
import CloudKit
import CoreData
import UserNotifications

/// The Assistant's one settings screen, behind the person button: whose
/// classroom this is and since when, what the tiles mean, which way the grid
/// runs and whether it's split by level, her name, the arrival, front-desk
/// email and early-pickup reminders, the background, the bells, and the way
/// out.
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
    /// Marks still on their way when she tapped Leave: asks Wait or Leave Anyway.
    @State private var unsentBeforeLeave: AssistantBootstrapper.UnsentMarks?
    @State private var isLeaving = false
    @State private var isSendingFirst = false
    @State private var leaveError: String?
    @State private var leaveNote: String?
    @AppStorage(ArrivalReminder.enabledKey) private var reminderOn = true
    @AppStorage(ArrivalReminder.timeKey) private var reminderMinutes = ArrivalReminder.defaultMinutes
    @AppStorage(FrontDeskEmailReminder.enabledKey) private var frontDeskOn = FrontDeskEmailReminder.isOnByDefault
    @AppStorage(FrontDeskEmailReminder.leadKey) private var frontDeskLead = FrontDeskEmailReminder.defaultLeadMinutes
    @AppStorage(EarlyPickupReminder.enabledKey) private var pickupOn = true
    @State private var notificationsDenied = false
    @AppStorage(AttendanceBells.enabledKey) private var bellsOn = false
    @AppStorage(AssistantGridOrder.key) private var gridOrderRaw = AssistantGridOrder.across.rawValue
    @AppStorage(AssistantLevelGroups.key) private var groupsByLevel = false
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
            .confirmationDialog(
                "Some marks haven't been sent",
                isPresented: Binding(
                    get: { unsentBeforeLeave != nil },
                    set: { if !$0 { unsentBeforeLeave = nil } }
                ),
                titleVisibility: .visible,
                presenting: unsentBeforeLeave
            ) { _ in
                Button("Wait") {
                    Task { await sendFirst() }
                }
                Button("Leave Anyway", role: .destructive) {
                    Task { await leave() }
                }
            } message: { unsent in
                Text(unsent.message)
            }
        }
    }

    // MARK: - Sections

    /// No header: the screen's title already says "Classroom".
    private var classroomSection: some View {
        Section {
            LabeledContent("Guide", value: guideName)
            if let joined {
                LabeledContent("Joined", value: joined.formatted(date: .abbreviated, time: .omitted))
            }
            if let classroomID {
                // Folded away: only for telling the guide which class this is.
                DisclosureGroup("Details") {
                    LabeledContent("Class code") {
                        Text(classroomID)
                            .monospaced()
                            .textSelection(.enabled)
                    }
                }
            }
        } footer: {
            if classroomID != nil {
                Text("If something looks wrong, read the class code under Details to your guide. "
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
                    Text("Notifications are off for this app.")
                    Button("Turn On in Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(reminderFooter, id: \.self) { Text($0) }
                }
            }
        }
        .task(id: "\(reminderOn)|\(reminderMinutes)|\(frontDeskOn)|\(frontDeskLead)") {
            await applyReminderSetting()
        }
    }

    /// Says what will actually happen with the switches as they are now: a
    /// short line for each reminder, not one long paragraph.
    private var reminderFooter: [String] {
        var lines: [String] = []
        if reminderOn {
            let at = FrontDeskEmailReminder.timeString(reminderMinutes)
            lines.append("Arrival: a reminder at \(at) on school days, unless every child is marked.")
        }
        if let dueAt = frontDeskDueAt {
            let nudge = " If no one has sent it, a reminder \(frontDeskLead) min before and at \(dueAt)."
            lines.append("Front desk: attendance is due by \(dueAt)." + (frontDeskOn ? nudge : ""))
        }
        if pickupOn {
            lines.append("Early pickups: hold a child's name and choose Leaving Early… "
                + "for a reminder before their time.")
        }
        return lines.isEmpty ? ["Turn on a reminder to get a nudge on school days."] : lines
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

    // MARK: - Values

    private var guideName: String { bootstrapper.guideNameToShow ?? "Your guide" }

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
}

// MARK: - Leaving

extension AssistantClassroomSheet {

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
            Button("Leave Classroom", role: .destructive, action: startLeave)
                .disabled(isLeaving || isSendingFirst)
            if isSendingFirst {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Sending your marks…").foregroundStyle(.secondary)
                }
            }
        } footer: {
            if let leaveError {
                Text(leaveError).foregroundStyle(.red)
            } else if let leaveNote {
                Text(leaveNote)
            }
        }
    }

    /// Leave purges the class at once, so marks still on their way are lost:
    /// with any, she's asked to wait first.
    private func startLeave() {
        leaveError = nil
        leaveNote = nil
        if let unsent = bootstrapper.unsentMarks() {
            unsentBeforeLeave = unsent
        } else {
            confirmingLeave = true
        }
    }

    /// Wait: tries to send them, then says how it went. Leave stays hers to tap.
    private func sendFirst() async {
        isSendingFirst = true
        let stillUnsent = await bootstrapper.sendUnsentMarks()
        isSendingFirst = false
        leaveNote = stillUnsent == nil
            ? "Your marks have reached your guide. You can leave now."
            : "Some marks still haven't gone. Check that this iPhone is online, then try again."
    }

    private func leave() async {
        isLeaving = true
        leaveError = nil
        leaveNote = nil
        do {
            try await bootstrapper.leaveClassroom()
            dismiss()
        } catch {
            leaveError = Self.leaveMessage(for: error)
        }
        isLeaving = false
    }

    /// Leave's own reasons (the class hasn't finished arriving, several
    /// classes, the leave not saved) say what to do; a CloudKit failure gets
    /// the sharing wording. They all used to read "Check that this iPhone is
    /// online".
    static func leaveMessage(for error: Error) -> String {
        AppErrorMessages.sharingMessage(for: error, action: "leave the classroom")
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
            Toggle("Group by Level", isOn: $groupsByLevel)
        } footer: {
            let order = AssistantGridOrder.resolved(gridOrderRaw) == .across
                ? "Names go A to Z across each row, then on to the next row."
                : "Names go A to Z down each column, then on to the next column."
            let blocks = "Upper Elementary, Adolescent and Lower Elementary each get their own block. "
            Text("\(groupsByLevel ? blocks : "")\(order) It only changes this iPhone.")
        }
    }
}
