import SwiftUI

// MARK: - Quick Capture Button

/// Look and feel › Quick capture: whether the floating button shows.
struct QuickCaptureButtonSettingsView: View {
    @AppStorage(UserDefaultsKeys.quickCaptureButtonVisible)
    private var isVisible = true

    var body: some View {
        SettingsGroup(.quickCapture, footer: Self.helpText) {
            Toggle("Show the floating button", isOn: $isVisible)
                .frame(maxWidth: .infinity)
        }
    }

    private static var helpText: String {
        #if os(macOS)
        "The floating button opens quick capture. Click and hold it for the pie menu of quick actions. "
            + "You can also show or hide it from the View menu."
        #else
        "The floating button opens quick capture. Touch and hold it for the pie menu of quick actions. "
            + "The + menu on Today offers the same actions."
        #endif
    }
}
