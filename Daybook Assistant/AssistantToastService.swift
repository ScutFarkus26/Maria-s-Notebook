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

    private func show(_ message: String, kind: Kind) {
        let toast = Toast(message: message, kind: kind)
        current = toast
        Task {
            try? await Task.sleep(for: .seconds(3))
            if current?.id == toast.id { current = nil }
        }
    }
}
