import SwiftUI

/// The one AI choice left in the app: whether a request the on-device model
/// can't finish may move to Apple's Private Cloud Compute.
struct PrivateCloudSettingsView: View {
    @AppStorage(UserDefaultsKeys.aiAllowAutomaticPrivateCloud)
    private var allowAutomaticPrivateCloud = false

    var body: some View {
        Toggle(isOn: $allowAutomaticPrivateCloud) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Allow Apple Private Cloud")
                Text(
                    "When off, the app's AI keeps student records on this device "
                        + "and stops if the on-device model can't finish."
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: allowAutomaticPrivateCloud) { _, _ in SettingsCategory.markModified(.aiFeatures) }
    }
}
