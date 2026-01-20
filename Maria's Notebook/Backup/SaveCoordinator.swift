import Foundation
import SwiftUI
import SwiftData
@preconcurrency import Combine

@MainActor
final class SaveCoordinator: ObservableObject {
    // Removed 'nonisolated' to fix "variable with non-'Sendable' type" error.
    // Since this class is @MainActor, this publisher becomes MainActor-isolated,
    // which matches how ObservableObject is typically used in SwiftUI.
    let objectWillChange = ObservableObjectPublisher()

    @Published var lastSaveError: Error?
    @Published var lastSaveErrorMessage: String?
    @Published var isShowingSaveError: Bool = false

    /// When true, suppress presenting UI alerts on save failures (used in previews)
    var suppressAlerts: Bool = false

    /// Perform a centralized SwiftData save with consistent error handling.
    /// - Parameters:
    ///   - context: The `ModelContext` to save.
    ///   - reason: Optional, short description of why the save is occurring (shown to the user on failure).
    /// - Returns: `true` if the save succeeded; `false` if it failed and an alert was prepared.
    @discardableResult
    func save(_ context: ModelContext, reason: String? = nil) -> Bool {
        // Avoid unnecessary writes if nothing changed
        if !context.hasChanges {
            return true
        }
        do {
            try context.save()
            return true
        } catch {
            let ns = error as NSError
            self.lastSaveError = error
            var message = ns.localizedDescription
            // Enrich message with underlying error if present
            if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
                message += "\nUnderlying: \(underlying.localizedDescription)"
            }
            if let why = reason, !why.trimmed().isEmpty {
                message = "\(why):\n\n\(message)"
            }
            self.lastSaveErrorMessage = message
            if !self.suppressAlerts && !self.isShowingSaveError {
                self.isShowingSaveError = true
            }
            return false
        }
    }

    /// Perform a save and show a success toast if it succeeds.
    /// - Parameters:
    ///   - context: The `ModelContext` to save.
    ///   - successMessage: Message to show in toast on success.
    ///   - reason: Optional, short description of why the save is occurring (shown to the user on failure).
    /// - Returns: `true` if the save succeeded; `false` if it failed.
    @discardableResult
    func saveWithToast(_ context: ModelContext, successMessage: String, reason: String? = nil) -> Bool {
        let success = save(context, reason: reason)
        if success {
            ToastService.shared.showSuccess(successMessage)
        }
        return success
    }

    /// Perform a save and show an info toast if it succeeds.
    /// - Parameters:
    ///   - context: The `ModelContext` to save.
    ///   - infoMessage: Message to show in toast on success.
    ///   - reason: Optional, short description of why the save is occurring (shown to the user on failure).
    /// - Returns: `true` if the save succeeded; `false` if it failed.
    @discardableResult
    func saveWithInfoToast(_ context: ModelContext, infoMessage: String, reason: String? = nil) -> Bool {
        let success = save(context, reason: reason)
        if success {
            ToastService.shared.showInfo(infoMessage)
        }
        return success
    }

    /// Clear any previously captured error state and dismiss the alert.
    func clearError() {
        lastSaveError = nil
        lastSaveErrorMessage = nil
        isShowingSaveError = false
    }
}

// Lightweight helper for previews so views can inject a coordinator without app wiring.
extension SaveCoordinator {
    static var preview: SaveCoordinator {
        let sc = SaveCoordinator()
        sc.suppressAlerts = true
        return sc
    }
}
// MARK: - Global save error alert modifier
private struct SaveErrorAlertModifier: ViewModifier {
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    func body(content: Content) -> some View {
        content
            .alert("Couldn't Save", isPresented: Binding(
                get: { saveCoordinator.isShowingSaveError },
                set: { newValue in if !newValue { saveCoordinator.clearError() } }
            )) {
                Button("OK") { saveCoordinator.clearError() }
            } message: {
                Text(saveCoordinator.lastSaveErrorMessage ?? "Unknown error.")
            }
    }
}

public extension View {
    /// Attach a global save error alert that listens to `SaveCoordinator`.
    func saveErrorAlert() -> some View {
        self.modifier(SaveErrorAlertModifier())
    }
}
