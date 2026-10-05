import SwiftUI
import CloudKit

// The pages before joining (`AssistantOnboardingView`).

// MARK: - Welcome

struct AssistantWelcomePage: View {
    let onStart: () -> Void

    /// The grid's look in one glance: here, not yet, absent, late.
    private static let sample: [(String, AttendanceStatus)] = [
        ("Ari", .present), ("Maya", .present), ("Noah", .unmarked),
        ("Leah", .present), ("Ezra", .absent), ("Tamar", .tardy),
        ("Miriam", .unmarked), ("Eli", .present), ("Rina", .present)
    ]

    var body: some View {
        AssistantOnboardingPage(
            title: "Assistant",
            message: "Take the morning roll for your classroom. Your guide sees each mark the moment you make it."
        ) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(Self.sample, id: \.0) { name, status in
                    AssistantKeyTile(status: status, name: name, height: 52)
                }
            }
            .padding(16)
            .background { AssistantBackdrop(isToday: true, isLate: false, hereFraction: 0.6, wallpaper: .sky) }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .environment(\.attendanceBackdropIsQuiet, true)
            .accessibilityHidden(true)
        } actions: {
            OnboardingPrimaryButton("Get Started", action: onStart)
            SampleClassButton()
        }
    }
}

/// Try a Sample Class, with the line that says what it is.
struct SampleClassButton: View {
    @Environment(AssistantBootstrapper.self) private var bootstrapper

    var body: some View {
        VStack(spacing: 0) {
            OnboardingSecondaryButton("Try a Sample Class") { bootstrapper.openSampleClass() }
            Text("Made-up names. Nothing is sent.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Practice

/// Nine made-up children on the Sky background, marked by the real grid's
/// rule, with the bottom bar's count and Close Arrival.
struct AssistantPracticePage: View {
    let onContinue: () -> Void
    @State private var roll = AssistantPracticeRoll()

    private var hint: String {
        if roll.phase == .late {
            return "Arrival's closed. Tap a latecomer and they're marked late."
        }
        if roll.unmarkedCount == 0 { return "Everyone's marked. That's the whole morning." }
        if roll.hereCount > 0 { return "When arrival is over, Close Arrival marks everyone left as absent." }
        return "Tap each child as they come in. Try it here: these are made-up names."
    }

    var body: some View {
        AssistantOnboardingPage(title: "One tap, and they're here", message: hint) {
            VStack(spacing: 12) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(AssistantPracticeRoll.names, id: \.self) { name in
                        tile(name)
                    }
                }
                bar
            }
            .padding(14)
            .background {
                AssistantBackdrop(
                    isToday: true,
                    isLate: roll.phase == .late,
                    hereFraction: Double(roll.hereCount) / Double(AssistantPracticeRoll.names.count),
                    wallpaper: .sky
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .environment(\.attendanceBackdropIsQuiet, true)

            Text("Names never move, so your thumb learns where each child is. Tap a mark again to take it back.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } actions: {
            OnboardingPrimaryButton("Continue", action: onContinue)
        }
    }

    private func tile(_ name: String) -> some View {
        let status = roll.status(of: name)
        return Button {
            withAnimation(.smooth(duration: 0.25)) { roll.tap(name) }
        } label: {
            AssistantKeyTile(status: status, name: name, height: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: status)
        .accessibilityLabel(name)
        .accessibilityValue(status == .unmarked ? "Not marked" : status.displayName)
    }

    private var bar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(roll.hereCount) of \(AssistantPracticeRoll.names.count) here")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text(roll.phase == .late
                    ? "\(roll.absentCount) absent"
                    : roll.unmarkedCount == 0 ? "Everyone's marked" : "\(roll.unmarkedCount) not marked yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            if roll.phase == .arrival {
                Button("Close Arrival") {
                    withAnimation(.smooth(duration: 0.3)) { roll.closeArrival() }
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            } else {
                Label("Late", systemImage: "clock.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.lateAmber.opacity(0.16), in: Capsule())
                    .foregroundStyle(Color.lateAmber)
                Button("Start Over") {
                    withAnimation(.smooth(duration: 0.3)) { roll.reset() }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - iCloud

/// Is this iPhone signed in to iCloud, with what that means for her: only the
/// class list, and marks that wait out a bad connection.
struct AssistantICloudPage: View {
    @Environment(AssistantBootstrapper.self) private var bootstrapper
    let onContinue: () -> Void

    private var status: CKAccountStatus? { bootstrapper.accountStatus }
    private var problem: String? { status?.assistantProblem }

    var body: some View {
        AssistantOnboardingPage(
            systemImage: problem == nil ? "checkmark.icloud" : "icloud.slash",
            tint: problem == nil ? .accentColor : .orange,
            title: problem == nil ? "Use your own iCloud" : "Sign in to iCloud first",
            message: problem == nil
                ? "Attendance travels through iCloud to your guide's notebook. Use the Apple Account that's yours, "
                    + "not your guide's."
                : "Attendance can't reach your guide without it."
        ) {
            if let problem {
                OnboardingNotice(text: problem, systemImage: "icloud.slash")
                VStack(alignment: .leading, spacing: 14) {
                    OnboardingStep(number: 1, text: "Open the Settings app.")
                    OnboardingStep(number: 2, text: "At the top, sign in with your own Apple Account.")
                    OnboardingStep(number: 3, text: "Come back here. This page checks again on its own.")
                }
            } else {
                OnboardingCard {
                    OnboardingCardRow(
                        title: status == nil ? "Checking iCloud…" : "Signed in to iCloud",
                        detail: status == nil ? nil : "This iPhone is ready to join a classroom.",
                        showsDivider: false
                    ) {
                        if status == nil {
                            ProgressView()
                        } else {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                    OnboardingCardRow(
                        title: "Only the class list",
                        detail: "You'll see the children's names and attendance. The rest of the notebook "
                            + "stays with your guide."
                    ) {
                        Image(systemName: "lock.fill").foregroundStyle(.tint)
                    }
                    OnboardingCardRow(
                        title: "Spotty Wi-Fi is fine",
                        detail: "Marks wait on this iPhone and send as soon as it's back online."
                    ) {
                        Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.tint)
                    }
                }
            }
        } actions: {
            OnboardingPrimaryButton("Continue", action: onContinue)
            if problem != nil {
                OnboardingSecondaryButton("Check Again") {
                    Task { await bootstrapper.refreshAccountStatus() }
                }
            }
        }
    }
}

// MARK: - Invitation

/// Where onboarding rests: open the guide's link. While the join runs it
/// shows that instead, and a failed join or an iCloud problem says what to do.
struct AssistantInvitationPage: View {
    @Environment(AssistantBootstrapper.self) private var bootstrapper

    private var isJoining: Bool { bootstrapper.sharingService?.isJoining ?? false }
    private var joinError: String? { bootstrapper.sharingService?.shareError }
    private var iCloudProblem: String? { bootstrapper.accountStatus?.assistantProblem }

    var body: some View {
        Group {
            if isJoining {
                joining
            } else {
                waiting
            }
        }
        .animation(.smooth, value: isJoining)
    }

    /// Check Again and the sample stay in reach while joining: a join can
    /// hang (it gives up after a minute, `ClassroomSharingService.joinTimeout`),
    /// and one that finishes later still lands here.
    private var joining: some View {
        AssistantOnboardingPage(
            systemImage: "house",
            title: "Joining your classroom",
            message: "This can take a minute. Keep the app open."
        ) {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
        } actions: {
            wayOut
        }
    }

    /// Check Again finds a join that finished, and the iCloud account.
    @ViewBuilder
    private var wayOut: some View {
        Button {
            bootstrapper.refreshMembership()
            Task { await bootstrapper.refreshAccountStatus() }
        } label: {
            Text("Check Again")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 16))
        .controlSize(.large)
        SampleClassButton()
    }

    /// A join that outlasted its minute isn't a wrong invitation.
    private var joinTimedOut: Bool { joinError == ClassroomSharingService.joinTimeoutMessage }

    private var waiting: some View {
        AssistantOnboardingPage(
            systemImage: joinError == nil ? "link" : "exclamationmark.triangle",
            tint: joinError == nil ? .accentColor : .orange,
            title: joinError == nil ? "Open your guide's invitation"
                : joinTimedOut ? "Joining didn't finish" : "That invitation didn't work",
            message: joinError == nil
                ? "Your guide sends it from the notebook. Open it on this iPhone and it brings you straight back here."
                : nil
        ) {
            if let joinError {
                OnboardingNotice(text: joinError, systemImage: "exclamationmark.triangle")
                if !joinTimedOut {
                    Text("Your guide invites you by the email or phone number on your Apple Account. If they used a "
                        + "different one, the link won't open here: ask them to use the one this iPhone is "
                        + "signed in with.")
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                if let iCloudProblem {
                    OnboardingNotice(text: iCloudProblem, systemImage: "icloud.slash")
                }
                VStack(alignment: .leading, spacing: 14) {
                    OnboardingStep(number: 1, text: "Your guide shares the classroom from the notebook.")
                    OnboardingStep(number: 2, text: "Open the link on this iPhone, in Messages or Mail.")
                    OnboardingStep(number: 3, text: "The class list appears here once you've joined.")
                }
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Waiting for the invitation…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .accessibilityElement(children: .combine)
            }
        } actions: {
            wayOut
        }
    }
}
