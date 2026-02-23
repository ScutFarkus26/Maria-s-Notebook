import Foundation
import SwiftUI
import SwiftData

@Observable
@MainActor
final class SaveCoordinator {
    var lastSaveError: Error?
    var lastSaveErrorMessage: String?
    var isShowingSaveError: Bool = false

    /// When true, suppress presenting UI alerts on save failures (used in previews)
    var suppressAlerts: Bool = false
    
    private let toastService: ToastService
    
    init(toastService: ToastService = ToastService.shared) {
        self.toastService = toastService
    }
    
    // Weak reference wrapper to safely hold ModelContext references
    private class WeakContextHolder {
        weak var context: ModelContext?
        let reason: String?
        
        init(context: ModelContext, reason: String?) {
            self.context = context
            self.reason = reason
        }
    }
    
    // Save batching to reduce database write contention
    private var pendingSaves: [ObjectIdentifier: WeakContextHolder] = [:]
    private var saveTimer: Timer?
    private let saveBatchInterval: TimeInterval = 0.5 // 500ms debounce

    /// Schedule a batched save operation (debounced by 500ms).
    /// Multiple save requests for the same context within the debounce window are coalesced.
    /// - Parameters:
    ///   - context: The `ModelContext` to save.
    ///   - reason: Optional, short description of why the save is occurring.
    func scheduleSave(_ context: ModelContext, reason: String? = nil) {
        let contextID = ObjectIdentifier(context)
        pendingSaves[contextID] = WeakContextHolder(context: context, reason: reason)
        
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: saveBatchInterval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.executePendingSaves()
            }
        }
    }
    
    /// Execute all pending saves immediately
    private func executePendingSaves() {
        let saves = pendingSaves
        pendingSaves.removeAll()
        
        for (_, holder) in saves {
            // Only save if context still exists
            guard let context = holder.context else { continue }
            save(context, reason: holder.reason)
        }
    }
    
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
            toastService.showSuccess(successMessage)
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
            toastService.showInfo(infoMessage)
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
    @Environment(SaveCoordinator.self) private var saveCoordinator

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
