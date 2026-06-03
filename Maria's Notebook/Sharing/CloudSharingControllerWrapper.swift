import SwiftUI
import CoreData
import CloudKit
import OSLog

#if os(iOS)
import UIKit

/// SwiftUI wrapper for UICloudSharingController on iOS.
///
/// Presents the system sharing UI for managing a CKShare.
/// The caller must provide an existing CKShare (create one via
/// ClassroomSharingService before presenting this sheet).
///
/// `onShareSaved` fires the moment the controller reports a successful
/// save — distinct from `onDismiss` so callers can synchronously
/// refresh share state (and trigger SharedStoreZoneRepair) before any
/// UI-driven dismissal work runs.
struct CloudSharingSheet: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    var onShareSaved: (() -> Void)?
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowReadWrite, .allowReadOnly]
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onShareSaved: onShareSaved, onDismiss: onDismiss)
    }

    class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let onShareSaved: (() -> Void)?
        let onDismiss: () -> Void

        init(onShareSaved: (() -> Void)?, onDismiss: @escaping () -> Void) {
            self.onShareSaved = onShareSaved
            self.onDismiss = onDismiss
        }

        func cloudSharingController(
            _ controller: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            Logger.app(category: "CloudSharing").error("Failed to save share: \(error.localizedDescription)")
        }

        func itemTitle(for controller: UICloudSharingController) -> String? {
            "Maria's Notebook Classroom"
        }

        func cloudSharingControllerDidSaveShare(_ controller: UICloudSharingController) {
            Logger.app(category: "CloudSharing").info("Share saved successfully")
            onShareSaved?()
            onDismiss()
        }

        func cloudSharingControllerDidStopSharing(_ controller: UICloudSharingController) {
            Logger.app(category: "CloudSharing").info("Sharing stopped")
            onDismiss()
        }
    }
}

#elseif os(macOS)
import AppKit

/// SwiftUI wrapper for CloudKit sharing on macOS.
///
/// Uses NSSharingService to present the macOS sharing UI.
///
/// `onShareSaved` is accepted for API parity with the iOS variant but
/// is not invoked on macOS — `NSSharingServicePicker` doesn't expose a
/// "share saved" signal. Callers should still refresh share state in
/// `onDismiss`.
struct CloudSharingSheet: NSViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    var onShareSaved: (() -> Void)?
    let onDismiss: () -> Void

    func makeNSViewController(context: Context) -> NSSharingServicePickerViewController {
        let itemProvider = NSItemProvider()
        itemProvider.registerCloudKitShare(share, container: container)
        let picker = NSSharingServicePicker(items: [itemProvider])
        return NSSharingServicePickerViewController(picker: picker, onDismiss: onDismiss)
    }

    func updateNSViewController(_ nsViewController: NSSharingServicePickerViewController, context: Context) {}
}

/// Minimal view controller wrapper for NSSharingServicePicker on macOS.
class NSSharingServicePickerViewController: NSViewController, NSSharingServicePickerDelegate {
    let picker: NSSharingServicePicker
    let onDismiss: () -> Void

    init(picker: NSSharingServicePicker, onDismiss: @escaping () -> Void) {
        self.picker = picker
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        picker.delegate = self
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker,
        didChoose service: NSSharingService?
    ) {
        if service == nil {
            onDismiss()
        }
    }
}
#endif
