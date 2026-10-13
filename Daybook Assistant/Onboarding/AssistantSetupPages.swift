import SwiftUI
import CoreData

// The last two pages of setup after joining (`AssistantSetupFlow`).

// MARK: - Symbols and the email

/// The tile symbols worth knowing on day one, drawn by the tile key's own
/// tile, and the front-desk email (or ParentLocker, once the guide picks it):
/// where its button appears and what "sent" looks like.
struct AssistantSetupSymbolsPage: View {
    @Environment(AssistantBootstrapper.self) private var bootstrapper
    let onContinue: () -> Void

    /// The guide's due time ("9:00 AM"), once the email's settings (or
    /// ParentLocker, picked) have arrived from the notebook.
    private var dueAt: String? {
        guard let context = bootstrapper.coreDataStack?.viewContext,
              let settings = AttendanceEmailLog.settings(in: context), settings.canSendAttendance else { return nil }
        return FrontDeskEmailReminder.timeString(settings.deadlineMinutes)
    }

    /// The guide picked ParentLocker: the card shows Close Arrival & Send.
    private var sendsToParentLocker: Bool {
        guard let context = bootstrapper.coreDataStack?.viewContext else { return false }
        return AttendanceEmailLog.settings(in: context)?.sendMethod == .parentLocker
    }

    var body: some View {
        AssistantOnboardingPage(title: "What the symbols mean") {
            VStack(alignment: .leading, spacing: 8) {
                OnboardingCard {
                    symbol(
                        AssistantKeyTile(
                            status: .unmarked, corner: AttendanceBirthday.birthday.symbol,
                            cornerColor: .pink, party: true
                        ),
                        "Birthday",
                        "Greet them at the door. An outline cake is a half-birthday, for summer birthdays.",
                        showsDivider: false
                    )
                    symbol(
                        AssistantKeyTile(status: .unmarked, name: "Noah", corner: "hand.wave.fill", cornerColor: .teal),
                        "Welcome back",
                        "Away \(AttendanceWelcomeBack.threshold) or more school days. Mark them in and the bar "
                            + "says “Welcome back, Noah.”"
                    )
                    symbol(AssistantKeyTile(status: .tardy, name: "Tamar"), "Late", "Came in after arrival closed.")
                    symbol(
                        AssistantKeyTile(status: .leftEarly, name: "Eli"), "Left early",
                        "Went home before the end of the day."
                    )
                    symbol(
                        AssistantKeyTile(status: .present, name: "Leah", note: true), "Note",
                        "Someone wrote a note. Hold the name to read it."
                    )
                }
                Text("Press and hold any name for absence reasons, Left Early, and notes. "
                    + "What the Tiles Mean, in Classroom, has the rest.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            emailCard
        } actions: {
            OnboardingPrimaryButton("Continue", action: onContinue)
        }
    }

    private func symbol(
        _ tile: AssistantKeyTile, _ title: String, _ detail: String, showsDivider: Bool = true
    ) -> some View {
        HStack(spacing: 14) {
            tile
                .frame(width: 76)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            if showsDivider { Divider().padding(.leading, 90) }
        }
        .accessibilityElement(children: .combine)
    }

    private var emailCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(sendsToParentLocker ? "Sending to ParentLocker" : "The front-desk email")
                    .font(.body.weight(.semibold))
                Text(sendsToParentLocker
                    ? "Close Arrival & Send sends the class to ParentLocker. Later changes follow by themselves."
                    : dueAt == nil
                    ? "If your guide sets it up, the morning's attendance email is one tap once arrival closes, "
                        + "written the way they want it."
                    : "One tap once arrival closes, written the way your guide set it up.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 6) {
                Label(
                    sendsToParentLocker ? "Close Arrival & Send" : "Close Arrival & Email",
                    systemImage: sendsToParentLocker ? "paperplane.fill" : "envelope.fill"
                )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Color.accentColor, in: Capsule())
                Text("Due \(sendsToParentLocker ? "in ParentLocker" : "at the front desk") by \(dueAt ?? "9:00 AM")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background { AssistantBackdrop(isToday: true, isLate: false, hereFraction: 0.9, wallpaper: .sky) }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityHidden(true)
            Label {
                Text(sendsToParentLocker
                    ? "Sent to ParentLocker 8:42 AM by \(ClassroomIdentity.displayName ?? "you")"
                    : "Front desk: Sent 8:42 by \(ClassroomIdentity.displayName ?? "you")")
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            Text("Once anyone sends it, everyone sees it went, so it never goes twice.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - All set

/// What she set, and the class arriving: the count of children climbs as
/// the class list comes down.
struct AssistantSetupDonePage: View {
    @Environment(AssistantBootstrapper.self) private var bootstrapper
    let onFinish: () -> Void
    @AppStorage(ArrivalReminder.enabledKey) private var reminderOn = true
    @AppStorage(ArrivalReminder.timeKey) private var reminderMinutes = ArrivalReminder.defaultMinutes
    @AppStorage(AssistantWallpaper.key) private var wallpaperRaw = AssistantWallpaper.standard.rawValue
    @State private var childCount = 0

    private var name: String { ClassroomIdentity.displayName ?? "" }

    /// With ParentLocker picked: she signs in once, in Classroom.
    static let parentLockerLine = "Sign in to ParentLocker once to send attendance."

    private var sendsToParentLocker: Bool {
        guard let context = bootstrapper.coreDataStack?.viewContext else { return false }
        return AttendanceEmailLog.settings(in: context)?.sendMethod == .parentLocker
    }

    var body: some View {
        AssistantOnboardingPage(
            systemImage: "checkmark.seal.fill",
            tint: .green,
            title: name.isEmpty ? "You're all set" : "You're all set, \(name)",
            message: "You're taking attendance for \(bootstrapper.guideNameToShow.map { "\($0)'s" } ?? "your guide's") "
                + "classroom."
        ) {
            OnboardingCard {
                summary("Children", value: childCount == 0 ? "Downloading from iCloud…" : "\(childCount)", first: true)
                summary("Your name", value: name.isEmpty ? "Not set" : name)
                summary(
                    "Arrival reminder",
                    value: reminderOn ? FrontDeskEmailReminder.timeString(reminderMinutes) : "Off"
                )
                summary("Background", value: AssistantWallpaper.resolved(wallpaperRaw).title)
            }
            if sendsToParentLocker {
                Text(Self.parentLockerLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Change any of this in Classroom: the person button above the grid.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } actions: {
            OnboardingPrimaryButton("Take Attendance", action: onFinish)
        }
        .task { await followChildCount() }
    }

    private func summary(_ title: String, value: String, first: Bool = false) -> some View {
        LabeledContent(title, value: value)
            .padding(.vertical, 14)
            .overlay(alignment: .top) {
                if !first { Divider() }
            }
    }

    /// Counts now and after every import, while the page is up.
    private func followChildCount() async {
        countChildren()
        let changes = NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange).map { _ in () }
        for await _ in changes {
            countChildren()
        }
    }

    private func countChildren() {
        guard let context = bootstrapper.coreDataStack?.viewContext else { return }
        childCount = SiriHost.roster(in: context).count
    }
}
