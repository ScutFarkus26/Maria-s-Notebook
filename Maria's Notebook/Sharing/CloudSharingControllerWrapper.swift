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
struct CloudSharingSheet: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowReadWrite, .allowReadOnly]
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
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
struct CloudSharingSheet: NSViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
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
