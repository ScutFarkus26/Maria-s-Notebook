// ToastService.swift
// Centralized toast/notification management for the app

import SwiftUI

/// Toast message types for different visual styles
enum ToastType {
    case success
    case info
    case warning
    case error

    var backgroundColor: Color {
        switch self {
        case .success: return Color.green.opacity(0.9)
        case .info: return Color.black.opacity(0.85)
        case .warning: return Color.orange.opacity(0.9)
        case .error: return Color.red.opacity(0.9)
        }
    }

    var iconName: String? {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .info: return nil
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
    }
}

/// A toast message to display
struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let type: ToastType
    let duration: TimeInterval

    init(_ message: String, type: ToastType = .info, duration: TimeInterval = 2.0) {
        self.message = message
        self.type = type
        self.duration = duration
    }

    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool {
        lhs.id == rhs.id
    }
}

/// Centralized toast service for displaying transient notifications
@Observable
@MainActor
final class ToastService {
    /// Shared instance for app-wide toast display
    static let shared = ToastService()

    /// The current toast message to display (nil when no toast is shown)
    private(set) var currentToast: ToastMessage?

    /// Queue of pending toasts
    private var toastQueue: [ToastMessage] = []

    /// Timer for auto-dismissing toasts
    private var dismissTask: Task<Void, Never>?

    private init() {}

    /// Show a toast message
    /// - Parameters:
    ///   - message: The message to display
    ///   - type: The type of toast (affects styling)
    ///   - duration: How long to show the toast (default 2 seconds)
    func show(_ message: String, type: ToastType = .info, duration: TimeInterval = 2.0) {
        let toast = ToastMessage(message, type: type, duration: duration)

        // If no toast is currently showing, show immediately
        if currentToast == nil {
            showToast(toast)
        } else {
            // Queue the toast
            toastQueue.append(toast)
        }
    }

    /// Show a success toast
    func showSuccess(_ message: String, duration: TimeInterval = 2.0) {
        show(message, type: .success, duration: duration)
    }

    /// Show an info toast
    func showInfo(_ message: String, duration: TimeInterval = 2.0) {
        show(message, type: .info, duration: duration)
    }

    /// Show a warning toast
    func showWarning(_ message: String, duration: TimeInterval = 2.5) {
        show(message, type: .warning, duration: duration)
    }

    /// Show an error toast (for non-critical errors that don't need an alert)
    func showError(_ message: String, duration: TimeInterval = 3.0) {
        show(message, type: .error, duration: duration)
    }

    /// Dismiss the current toast immediately
    func dismiss() {
        dismissTask?.cancel()
        withAnimation(.easeInOut(duration: 0.25)) {
            currentToast = nil
        }
        showNextToast()
    }

    /// Clear all toasts (current and queued)
    func clearAll() {
        dismissTask?.cancel()
        toastQueue.removeAll()
        withAnimation(.easeInOut(duration: 0.25)) {
            currentToast = nil
        }
    }

    // MARK: - Private

    private func showToast(_ toast: ToastMessage) {
        dismissTask?.cancel()

        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            currentToast = toast
        }

        // Schedule auto-dismiss
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(toast.duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func showNextToast() {
        guard !toastQueue.isEmpty else { return }

        // Small delay before showing next toast
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
            guard !Task.isCancelled else { return }

            if let nextToast = self?.toastQueue.first {
                self?.toastQueue.removeFirst()
                self?.showToast(nextToast)
            }
        }
    }
}

// MARK: - Toast View

/// A view that displays the current toast message
struct ToastOverlay: View {
    @Bindable var toastService: ToastService

    var body: some View {
        Group {
            if let toast = toastService.currentToast {
                ToastView(toast: toast)
                    .onTapGesture {
                        toastService.dismiss()
                    }
            }
        }
    }
}

/// The actual toast view component
struct ToastView: View {
    let toast: ToastMessage

    var body: some View {
        HStack(spacing: 8) {
            if let iconName = toast.type.iconName {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
            }

            Text(toast.message)
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(toast.type.backgroundColor)
        )
        .foregroundColor(.white)
        .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - View Modifier

/// View modifier to add toast overlay to a view
struct ToastOverlayModifier: ViewModifier {
    @Bindable var toastService: ToastService

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                ToastOverlay(toastService: toastService)
                    .padding(.top, 8)
            }
    }
}

extension View {
    /// Add toast overlay support to a view (requires explicit service parameter)
    func toastOverlay(_ service: ToastService) -> some View {
        modifier(ToastOverlayModifier(toastService: service))
    }
}

// MARK: - Preview Support

extension ToastService {
    /// Preview instance with suppressed auto-dismiss
    static var preview: ToastService {
        let service = ToastService()
        return service
    }
}
