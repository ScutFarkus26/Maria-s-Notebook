import SwiftUI

/// A non-blocking banner shown while `NSPersistentCloudKitContainer` performs its
/// initial `setup`/`import` from iCloud, so a freshly launched or freshly signed-in
/// device shows "Syncing from iCloud…" instead of an empty-looking screen.
///
/// Apple's guidance (TN3163 / TN3164): the first import on a new device "can take
/// minutes, or longer." Surfacing that state — rather than leaving the user staring
/// at an empty database — is the recommended remedy. The banner is driven by
/// ``CloudKitSyncStatusService/isImportingFromCloud``, which is true only during
/// setup/import events (never routine local-save exports), so it appears at launch
/// and quietly disappears once the import completes.
struct SyncingFromICloudOverlay: ViewModifier {
    var syncService = CloudKitSyncStatusService.shared

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if syncService.isImportingFromCloud {
                    SyncingFromICloudBanner()
                        .padding(.top, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: syncService.isImportingFromCloud)
    }
}

/// The pill-shaped progress banner itself. Kept private to the overlay.
private struct SyncingFromICloudBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 1) {
                Text("Syncing from iCloud…")
                    .font(.subheadline.weight(.semibold))
                Text("Your data is downloading. This can take a moment.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.quaternary, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Syncing from iCloud. Your data is downloading.")
    }
}

extension View {
    /// Overlays a "Syncing from iCloud…" banner while CloudKit's initial import runs.
    func syncingFromICloudOverlay() -> some View {
        modifier(SyncingFromICloudOverlay())
    }
}
