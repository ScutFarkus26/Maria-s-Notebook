import Foundation
import SwiftUI

@MainActor
enum PresentationDetailUtilities {
    static func notifyInboxRefresh() {
        AppRouter.shared.refreshPlanningInbox()
    }
}
