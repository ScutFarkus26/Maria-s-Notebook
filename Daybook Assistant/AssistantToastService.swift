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

    func showSuccess(_ message: String) { show(message, kind: .success) }
    func showError(_ message: String) { show(message, kind: .error) }
    func showInfo(_ message: String) { show(message, kind: .info) }

    private func show(_ message: String, kind: Kind) {
        let toast = Toast(message: message, kind: kind)
        current = toast
        Task {
            try? await Task.sleep(for: .seconds(3))
            if current?.id == toast.id { current = nil }
        }
    }
}

/// Presents whatever `ToastService` is currently showing.
struct AssistantToastOverlay: View {
    @State private var service = ToastService.shared

    var body: some View {
        if let toast = service.current {
            HStack(spacing: 8) {
                Image(systemName: icon(for: toast.kind))
                Text(toast.message)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .foregroundStyle(toast.kind == .error ? .red : .primary)
            .padding(.horizontal, 20)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func icon(for kind: ToastService.Kind) -> String {
        switch kind {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
}
