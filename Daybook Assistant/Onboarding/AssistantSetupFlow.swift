import SwiftUI
import AppIntents
import CoreData
import UserNotifications

/// The first run after joining, over the attendance screen: her name, the
/// arrival reminder, a background, Siri, what the tile symbols and the
/// front-desk email look like, then All Set. The class list keeps coming
/// down from iCloud underneath while she goes through it.
///
/// Only the name is required (`AssistantNameSheet`'s reason: a term's marks
/// under no name at all). The reminder page is where iOS asks about
/// notifications, in context, instead of the moment the grid first appears.
/// Everything here is in Classroom afterwards.
struct AssistantSetupFlow: View {
    let onFinish: () -> Void

    enum Step: Hashable {
        case reminder, background, siri, symbols, allSet
    }

    @State private var path: [Step] = []

    var body: some View {
        NavigationStack(path: $path) {
            AssistantSetupNamePage { path.append(.reminder) }
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .reminder:
                        AssistantSetupReminderPage { path.append(.background) }
                    case .background:
                        AssistantSetupBackgroundPage { path.append(.siri) }
                    case .siri:
                        AssistantSetupSiriPage { path.append(.symbols) }
                    case .symbols:
                        AssistantSetupSymbolsPage { path.append(.allSet) }
                    case .allSet:
                        AssistantSetupDonePage {
                            AssistantOnboarding.markSetupDone()
                            onFinish()
                        }
                    }
                }
        }
        .interactiveDismissDisabled()
    }
}

// MARK: - Name

/// Required: Continue waits for a name. A name restored from iCloud (a new
/// iPhone) is already filled in, or fills in when it arrives.
struct AssistantSetupNamePage: View {
    let onContinue: () -> Void
    @Environment(AssistantBootstrapper.self) private var bootstrapper
    @State private var name = ClassroomIdentity.displayName ?? ""
    @AppStorage(UserDefaultsKeys.classroomIdentityDisplayName) private var storedName: String?
    @FocusState private var isFocused: Bool

    private var trimmed: String { name.trimmed() }

    var body: some View {
        AssistantOnboardingPage(
            systemImage: "person.crop.circle",
            title: "Who's marking?",
            message: "Your guide sees this beside the attendance you take, so your marks can be told apart "
                + "from anyone else's. First name is plenty."
        ) {
            TextField("First name", text: $name)
                .textContentType(.givenName)
                .autocorrectionDisabled()
                .submitLabel(.continue)
                .onSubmit(save)
                .focused($isFocused)
                .font(.title3)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                // Grows with the text size: a fixed 54 pt clipped the
                // largest sizes (bug hunt 2026-10-20 #25).
                .frame(minHeight: 54)
                .background(
                    Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .accessibilityLabel("Your name")

            VStack(alignment: .leading, spacing: 8) {
                Text("What your guide sees")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                OnboardingCard {
                    marked(.present, child: "Maya", at: "8:02", showsDivider: false)
                    marked(.tardy, child: "Tamar", at: "8:31")
                }
            }
        } actions: {
            OnboardingPrimaryButton("Continue", isEnabled: !trimmed.isEmpty, action: save)
        }
        .onAppear { if trimmed.isEmpty { isFocused = true } }
        .onChange(of: storedName) { _, stored in
            if let restored = AssistantNameSheet.restoredName(typed: name, stored: stored) { name = restored }
        }
    }

    private func marked(
        _ status: AttendanceStatus, child: String, at time: String, showsDivider: Bool = true
    ) -> some View {
        HStack(spacing: 14) {
            AssistantKeyTile(status: status, name: child, height: 34)
                .frame(width: 76)
            Text("\(status.displayName) at \(time) · by \(trimmed.isEmpty ? "you" : trimmed)")
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            if showsDivider { Divider() }
        }
        .accessibilityElement(children: .combine)
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        // Set now, so the tabs' name sheet never sees a moment without it.
        AssistantNameSheet.commit(trimmed, in: bootstrapper.coreDataStack)
        isFocused = false
        onContinue()
    }
}

// MARK: - Reminder

/// The arrival reminder's time, what it looks like, and the one place iOS
/// asks to allow notifications. Not Now turns the reminders off; Classroom
/// turns them back on. A refusal stays on the page with the way to Settings,
/// rather than moving on as if the reminder would ring.
struct AssistantSetupReminderPage: View {
    @Environment(AssistantBootstrapper.self) private var bootstrapper
    @Environment(\.scenePhase) private var scenePhase
    let onContinue: () -> Void
    @AppStorage(ArrivalReminder.timeKey) private var reminderMinutes = ArrivalReminder.defaultMinutes
    @State private var isAsking = false
    /// She was asked and said no (or had before): shown until she allows
    /// them in Settings and comes back.
    @State private var refused = false

    var body: some View {
        AssistantOnboardingPage(
            systemImage: "bell",
            title: "A reminder when arrival closes",
            message: "On school mornings, if anyone still isn't marked, you'll get a reminder to close arrival. "
                + "Weekends and days off are skipped."
        ) {
            DatePicker(
                "Remind me at",
                selection: ArrivalReminder.timeOfDay($reminderMinutes),
                displayedComponents: .hourAndMinute
            )
            .font(.body.weight(.semibold))
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text("It looks like this")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                notificationPreview
            }
        } actions: {
            if refused {
                // Pinned with the buttons, so the largest text on an SE
                // doesn't push it below the fold (review (d), #3). Held to the
                // first accessibility size, so at the largest the page above
                // keeps room to scroll and the notice isn't cut off.
                Group {
                    OnboardingNotice(text: AssistantSetupReminder.refusedLine, systemImage: "bell.slash")
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 4)
                    OnboardingSecondaryButton("Open Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                OnboardingPrimaryButton("Continue", action: onContinue)
            } else {
                OnboardingPrimaryButton("Turn On Reminder", isEnabled: !isAsking) {
                    Task { await turnOn() }
                }
                OnboardingSecondaryButton("Not Now") {
                    AssistantSetupReminder.decline()
                    onContinue()
                }
                // Not both at once: a Not Now while Turn On waits on iOS
                // would be undone by its answer.
                .disabled(isAsking)
            }
        }
        .animation(.smooth, value: refused)
        // Back from Settings: allowed there, the notice goes.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, refused else { return }
            Task {
                let status = await SystemReminderCenter().authorizationStatus()
                refused = AssistantSetupReminder.notificationsOff(status)
            }
        }
    }

    private var notificationPreview: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(.tint)
                .frame(width: 38, height: 38)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    // As the notification shows it: the Home Screen name.
                    Text("Assistant")
                    Spacer()
                    Text(FrontDeskEmailReminder.timeString(reminderMinutes))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(ArrivalReminder.notificationTitle)
                    .font(.subheadline.weight(.semibold))
                Text(ArrivalReminder.notificationBody)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Example notification: \(ArrivalReminder.notificationTitle). \(ArrivalReminder.notificationBody)"
        )
    }

    private func turnOn() async {
        isAsking = true
        let allowed = await AssistantSetupReminder.turnOn()
        if let context = bootstrapper.coreDataStack?.viewContext {
            await ArrivalReminder.reschedule(in: context)
        }
        isAsking = false
        if allowed {
            onContinue()
        } else {
            refused = true
        }
    }
}

// MARK: - Background

/// Classroom → Background itself, with Continue under it.
struct AssistantSetupBackgroundPage: View {
    let onContinue: () -> Void

    var body: some View {
        AssistantWallpaperPicker()
            .navigationTitle("Pick a Background")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                OnboardingPrimaryButton("Continue", action: onContinue)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
                    .background(.background)
            }
    }
}

// MARK: - Siri

/// What to say, with a child from this class in the examples once the class
/// list has arrived.
struct AssistantSetupSiriPage: View {
    @Environment(AssistantBootstrapper.self) private var bootstrapper
    let onContinue: () -> Void

    /// Three first names from the class, as the grid shows them, or made-up
    /// ones until the class list arrives.
    private var names: [String] {
        guard let context = bootstrapper.coreDataStack?.viewContext else { return Self.fallback }
        let students = SiriHost.roster(in: context)
        let shown = SiriHost.displayNames(for: students)
        let picked = students.prefix(3).compactMap { shown[$0.objectID] }
        return picked.count == 3 ? picked : Self.fallback
    }

    private static let fallback = ["Noah", "Tamar", "Ezra"]

    var body: some View {
        let names = names
        AssistantOnboardingPage(
            systemImage: "waveform",
            title: "Hands full? Ask Siri.",
            message: "Say any of these at the door, or type them to Siri. Undo asks you to unlock first."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                phrase("Mark \(names[0]) here in Daybook Assistant")
                phrase("\(names[1]) is late in Daybook Assistant")
                phrase("Mark \(names[2]) absent in Daybook Assistant")
                phrase("Who's absent in Daybook Assistant")
                phrase("Close arrival in Daybook Assistant")
            }
            ShortcutsLink()
                .shortcutsLinkStyle(.automaticOutline)
                .frame(maxWidth: .infinity)
        } actions: {
            OnboardingPrimaryButton("Continue", action: onContinue)
        }
    }

    private func phrase(_ text: String) -> some View {
        Text("“\(text)”")
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                Color(.secondarySystemBackground),
                in: UnevenRoundedRectangle(
                    topLeadingRadius: 18, bottomLeadingRadius: 6, bottomTrailingRadius: 18, topTrailingRadius: 18,
                    style: .continuous
                )
            )
    }
}
