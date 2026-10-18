// Bug hunt 2026-10-17 #38: a second toast was cut short by the first one's
// timer, which cleared whatever the banner was showing.

import OSLog
import SwiftUI
import Testing
@testable import CosmicDaybook

@Suite("Toast banner timing (Fix1017Sh)", .serialized)
@MainActor
struct ToastBannerFix1017ShTests {
    private final class Banner {
        var message: String?
    }

    private func binding(_ banner: Banner) -> Binding<String?> {
        Binding(get: { banner.message }, set: { banner.message = $0 })
    }

    @Test("A second toast isn't cut short by the first one's timer")
    func secondToastKeepsItsTime() async throws {
        let banner = Banner()
        let toast = binding(banner)

        EmptyView().showToast("All marked present", in: toast, logger: .ui, duration: .milliseconds(500))
        try await Task.sleep(for: .milliseconds(150))
        EmptyView().showToast("Attendance cleared", in: toast, logger: .ui, duration: .seconds(5))
        // Well past the first toast's half second, well inside the second's five.
        try await Task.sleep(for: .milliseconds(1_500))

        #expect(banner.message == "Attendance cleared")
    }

    @Test("A toast clears itself when its time is up")
    func toastClearsItself() async throws {
        let banner = Banner()
        EmptyView().showToast("All marked present", in: binding(banner), logger: .ui, duration: .milliseconds(200))
        #expect(banner.message == "All marked present")

        for _ in 0..<60 where banner.message != nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(banner.message == nil)
    }
}
