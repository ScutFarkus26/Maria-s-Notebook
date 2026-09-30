import SwiftUI

// MARK: - What's New Banner

/// A dismissible card with the newest release's notes (`SettingsWhatsNew`).
/// Dismissed per release, not per app version, so it comes back only when there is something new to read.
struct WhatsNewBanner: View {
    @AppStorage(UserDefaultsKeys.whatsNewDismissedRelease) private var dismissedReleaseID = ""

    var body: some View {
        if let release = SettingsWhatsNew.releaseToShow(dismissedID: dismissedReleaseID) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                HStack {
                    Label("What’s new", systemImage: "sparkles")
                        .font(AppTheme.ScaledFont.bodySemibold)
                        .foregroundStyle(.tint)
                    Spacer()
                    Button {
                        adaptiveWithAnimation(.easeInOut(duration: 0.25)) {
                            dismissedReleaseID = release.id
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss What’s new")
                }
                ForEach(release.notes, id: \.self) { note in
                    Label {
                        Text(note.text)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: note.symbol)
                            .foregroundStyle(.tint)
                    }
                    .font(AppTheme.ScaledFont.body)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(SettingsStyle.compactPadding)
            .surface(
                SettingsStyle.cornerRadius,
                fill: Color.accentColor.opacity(UIConstants.OpacityConstants.veryFaint),
                stroke: Color.accentColor.opacity(UIConstants.OpacityConstants.accent),
                style: .continuous
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct WhatsNewBannerPreview: View {
    var body: some View {
        WhatsNewBanner()
            .padding()
            .frame(maxWidth: 520)
    }
}

#Preview {
    WhatsNewBannerPreview()
}
