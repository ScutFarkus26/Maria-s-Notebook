import Foundation
import SwiftUI

enum StudentLessonDetailUtilities {
    enum Formatters {
        static let scheduleDay: DateFormatter = {
            let f = DateFormatter()
            f.setLocalizedDateFormatFromTemplate("EEEE, MMM d")
            return f
        }()
    }

    static func notifyInboxRefresh() {
        NotificationCenter.default.post(name: Notification.Name("PlanningInboxNeedsRefresh"), object: nil)
    }
}
