#if os(iOS)
import UIKit
import CloudKit

/// Handles CloudKit share acceptance on iOS.
///
/// When a user taps a share link, iOS delivers the CKShare.Metadata
/// through this delegate method. We post a notification that
/// ClassroomSharingService observes to process the acceptance.
@MainActor
final class ShareAcceptanceAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        NotificationCenter.default.post(
            name: .didAcceptCloudKitShare,
            object: cloudKitShareMetadata
        )
    }
}
#endif
