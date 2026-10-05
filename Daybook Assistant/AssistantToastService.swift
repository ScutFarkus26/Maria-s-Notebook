import SwiftUI
import Observation

/// Minimal stand-in for the main app's `ToastService`.
///
/// The shared save and sharing code announces failures through
/// `ToastService.shared`. The real one carries the notebook's theming, haptics
/// and animation helpers — a chain of UI dependencies this app has no use for.
/// It declares the same call sites and nothing else, so the shared files
/// compile here unchanged.
@MainActor
@Observable
final class ToastService {
    static let shared = ToastService()

    enum Kind { case success, error, info }

    struct Toast: Identifiable {
        let id = UUID()
        let message: String
        let kind: Kind
    }

    private(set) var current: Toast?

    private init() {}

    func showError(_ message: String) { show(message, kind: .error) }

    /// How long a message stays up: long enough to read, at about 15
    /// characters a second after a moment to notice it, between 4 and 10
    /// seconds.
    nonisolated static func duration(for message: String) -> Duration {
        let seconds = 2 + Double(message.count) / 15
        return .milliseconds(Int(min(max(seconds, 4), 10) * 1000))
    }

    private func show(_ message: String, kind: Kind) {
        let toast = Toast(message: message, kind: kind)
        current = toast
        // VoiceOver doesn't notice text appearing over the screen on its own.
        AccessibilityNotification.Announcement(message).post()
        Task {
            try? await Task.sleep(for: Self.duration(for: message))
            if current?.id == toast.id { current = nil }
        }
    }
}
