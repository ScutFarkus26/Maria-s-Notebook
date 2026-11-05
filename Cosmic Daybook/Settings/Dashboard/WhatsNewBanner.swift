import SwiftUI

// MARK: - What's New Row

/// One row at the top of the Settings list with the newest release's notes,
/// folded until opened. Hidden per release, not per app version, so it comes
/// back only when there is something new to read: a new release changes `releaseID`.
struct WhatsNewBanner: View {
    /// What a dismissal remembers.
    static let releaseID = "2026-09-settings"

    /// The release's notes: a symbol and a short line in the classroom voice.
    static let notes: [(symbol: String, text: String)] = [
        ("waveform", "Siri can take attendance now. Try “Mark Maya late” or “Undo attendance.”"),
        ("magnifyingglass", "Settings has a new home for everything, and search takes you straight to the setting."),
        ("clock.arrow.circlepath", "Backups can now run every few hours while the app is open.")
    ]

    @AppStorage(UserDefaultsKeys.whatsNewDismissedRelease) private var dismissedReleaseID = ""

    var body: some View {
        if dismissedReleaseID != Self.releaseID {
            DisclosureGroup {
                ForEach(Self.notes, id: \.text) { note in
                    Label {
                        Text(note.text)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: note.symbol)
                            .foregroundStyle(.tint)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                Button("Hide Until the Next Update") {
                    dismissedReleaseID = Self.releaseID
                }
                .font(.subheadline)
            } label: {
                Label("What’s new", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
    }
}
