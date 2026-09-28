#if os(iOS)
import UIKit
import CloudKit

/// Routes accepted CloudKit share invitations into the app on iOS.
///
/// Both apps are scene-based (a SwiftUI `WindowGroup`), and a scene-based app
/// is never sent `application(_:userDidAcceptCloudKitShareWith:)` — iOS hands
/// the invitation to the window scene's delegate instead. This delegate's only
/// job is to install `ShareAcceptanceSceneDelegate` on every scene.
final class ShareAcceptanceAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = ShareAcceptanceSceneDelegate.self
        return configuration
    }
}

/// Receives an accepted invitation by either of the two routes iOS uses: the
/// connection options when tapping the link is what launched the app, and
/// `windowScene(_:userDidAcceptCloudKitShareWith:)` when it was already running.
final class ShareAcceptanceSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            ShareInvitationInbox.deliver(metadata)
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        ShareInvitationInbox.deliver(cloudKitShareMetadata)
    }
}
#endif
