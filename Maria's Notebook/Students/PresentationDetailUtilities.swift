import Foundation
import SwiftUI

@MainActor
enum PresentationDetailUtilities {
    enum Formatters {
        static let scheduleDay: DateFormatter = {
            let f = DateFormatter()
            f.setLocalizedDateFormatFromTemplate("EEEE, MMM d")
            return f
        }()
    }

    static func notifyInboxRefresh() {
        AppRouter.shared.refreshPlanningInbox()
    }
}
