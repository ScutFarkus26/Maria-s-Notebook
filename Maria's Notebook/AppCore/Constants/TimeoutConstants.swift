import Foundation

enum TimeoutConstants {
    /// Default sync timeout in nanoseconds (10 seconds)
    static let defaultSyncTimeout: UInt64 = 10_000_000_000

    /// Offscreen coordinate for hidden UI elements
    static let offscreenCoordinate: CGFloat = -10000
}
