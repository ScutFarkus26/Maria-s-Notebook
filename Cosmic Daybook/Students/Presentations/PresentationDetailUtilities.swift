import Foundation
import SwiftUI
import CoreData

enum PresentationDetailUtilities {
    static func notifyInboxRefresh() {
        AppRouter.shared.refreshPlanningInbox()
    }
}
