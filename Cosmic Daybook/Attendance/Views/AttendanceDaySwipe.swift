import CoreGraphics

/// A sideways swipe across an attendance grid steps a school day. Only a
/// clearly sideways drag counts, so scrolling the grid never changes the day.
enum AttendanceDaySwipe {
    /// True to go forward (swiped left), false to go back, nil for a drag
    /// that isn't a day swipe.
    static func step(for translation: CGSize) -> Bool? {
        let dx = translation.width
        let dy = translation.height
        guard abs(dx) > 80, abs(dx) > abs(dy) * 2 else { return nil }
        return dx < 0
    }
}
