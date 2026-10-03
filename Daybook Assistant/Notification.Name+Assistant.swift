import Foundation

extension Notification.Name {
    /// A reminder was tapped: the attendance screen moves to today.
    static let assistantShowToday = Notification.Name("Assistant.showToday")
    /// Siri marked a staple or added to the office run: the Restock tab reloads.
    static let restockChangedBySiri = Notification.Name("Assistant.restockChangedBySiri")
}
