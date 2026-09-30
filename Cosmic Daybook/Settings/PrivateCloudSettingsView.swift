import SwiftUI

/// The one AI choice left in the app: whether a request the on-device model
/// can't finish may move to Apple's Private Cloud Compute.
struct PrivateCloudSettingsView: View {
    @AppStorage(UserDefaultsKeys.aiAllowAutomaticPrivateCloud)
    private var allowAutomaticPrivateCloud = false

    var body: some View {
        Toggle(isOn: $allowAutomaticPrivateCloud) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                Text("Allow Private Cloud Compute")
                Text(
                    "When on, a request too big for this device can finish on Apple's servers, "
                        + "which don't keep your data. When off, student records never leave this "
                        + "device, and a request the on-device model can't finish stops."
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
