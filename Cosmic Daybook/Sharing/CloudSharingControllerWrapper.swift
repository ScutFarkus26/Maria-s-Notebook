import SwiftUI
import CoreData
import CloudKit
import OSLog

#if os(iOS)
import UIKit

/// SwiftUI wrapper for UICloudSharingController on iOS.
///
/// Presents the system sharing UI for managing a CKShare.
/// The caller must provide the pinned classroom share, checked by
/// `ClassroomSharingService.shareForInvitations` before presenting this sheet.
///
/// `onShareSaved` fires the moment the controller reports a successful
/// save — distinct from `onDismiss` so callers can synchronously
/// refresh share state before any UI-driven dismissal work runs.
///
/// `onStopSharing` fires when the user ends the share from inside the
/// controller. NSPersistentCloudKitContainer observes the system sharing
/// UI and updates its own store metadata (iOS 16.4+), but the app's
/// published share/membership state still needs an explicit resync —
/// without it the UI keeps reporting the dead share until relaunch.
struct CloudSharingSheet: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    var onShareSaved: (() -> Void)?
    var onStopSharing: (() -> Void)?
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowReadWrite, .allowReadOnly]
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onShareSaved: onShareSaved, onStopSharing: onStopSharing, onDismiss: onDismiss)
    }

    class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let onShareSaved: (() -> Void)?
        let onStopSharing: (() -> Void)?
        let onDismiss: () -> Void

        init(
            onShareSaved: (() -> Void)?,
            onStopSharing: (() -> Void)?,
            onDismiss: @escaping () -> Void
        ) {
            self.onShareSaved = onShareSaved
            self.onStopSharing = onStopSharing
            self.onDismiss = onDismiss
        }

        func cloudSharingController(
            _ controller: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            Logger.cloudSharing.error("Failed to save share: \(error.localizedDescription)")
        }

        func itemTitle(for controller: UICloudSharingController) -> String? {
            "Cosmic Daybook Classroom"
        }

        func cloudSharingControllerDidSaveShare(_ controller: UICloudSharingController) {
            Logger.cloudSharing.info("Share saved successfully")
            onShareSaved?()
            onDismiss()
        }

        func cloudSharingControllerDidStopSharing(_ controller: UICloudSharingController) {
            Logger.cloudSharing.info("Sharing stopped")
            onStopSharing?()
            onDismiss()
        }
    }
}

#endif
