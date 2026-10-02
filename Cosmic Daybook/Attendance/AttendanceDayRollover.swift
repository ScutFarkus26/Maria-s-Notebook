import Foundation

/// Keeps an attendance screen on "today" across midnight without pulling it
/// off a day the guide chose on purpose.
///
/// `anchor` is the school day that stood for today when the screen last
/// looked. When today moves on, the screen follows only if it was still
/// showing that day, so "Mark N Present" after an overnight sleep lands
/// on the new day instead of overwriting yesterday.
enum AttendanceDayRollover {
    static func advance(
        selected: Date, anchor: Date?, newAnchor: Date
    ) -> (selected: Date, anchor: Date) {
        guard newAnchor != anchor else { return (selected, newAnchor) }
        let follows = anchor == nil || selected == anchor
        return (follows ? newAnchor : selected, newAnchor)
    }
}
