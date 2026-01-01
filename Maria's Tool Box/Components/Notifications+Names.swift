import Foundation

extension Notification.Name {
    /// Posted when the Planning inbox or agenda data changes and other views (e.g., Today) should refresh.
    static let PlanningInboxNeedsRefresh = Notification.Name("PlanningInboxNeedsRefresh")
}
