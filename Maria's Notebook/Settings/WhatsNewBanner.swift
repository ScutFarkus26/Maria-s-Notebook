import SwiftUI

// MARK: - What's New Banner

/// A dismissible banner showing recently added settings features.
/// Dismissed per app version — shows again when the app updates.
struct WhatsNewBanner: View {
    @AppStorage(UserDefaultsKeys.whatsNewDismissedVersion) private var dismissedVersion = ""

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private let newFeatures: [(icon: String, text: String)] = [
        ("magnifyingglass", "Enhanced settings search with deep indexing"),
        ("chart.bar.xaxis", "Settings dashboard overview"),
        ("circle.fill", "Connection status indicators in sidebar"),
        ("arrow.triangle.2.circlepath", "Sync history log")
    ]

    private var shouldShow: Bool {
        dismissedVersion != currentVersion
    }

    var body: some View {
        if shouldShow {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("What's New", systemImage: "sparkles")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.tint)
                    Spacer()
                    Button {
                        adaptiveWithAnimation(.easeInOut(duration: 0.25)) {
                            dismissedVersion = currentVersion
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(newFeatures, id: \.text) { feature in
                    Label(feature.text, systemImage: feature.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(SettingsStyle.compactPadding)
            .background(
                RoundedRectangle(cornerRadius: SettingsStyle.cornerRadius, style: .continuous)
                    .fill(Color.accentColor.opacity(UIConstants.OpacityConstants.veryFaint))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsStyle.cornerRadius, style: .continuous)
                    .stroke(Color.accentColor.opacity(UIConstants.OpacityConstants.accent))
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}
