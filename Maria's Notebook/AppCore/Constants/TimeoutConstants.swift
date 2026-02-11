import Foundation

enum TimeoutConstants {
    /// Default sync timeout (10 seconds)
    static let defaultSyncTimeout: Duration = .seconds(10)

    /// Offscreen coordinate for hidden UI elements
    static let offscreenCoordinate: CGFloat = -10000
}
