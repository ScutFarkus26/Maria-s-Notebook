import Foundation
import SwiftUI
import CoreData

@MainActor
enum PresentationDetailUtilities {
    static func notifyInboxRefresh() {
        AppRouter.shared.refreshPlanningInbox()
    }
}
