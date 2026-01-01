import Foundation

public enum DebugTiming {
    #if DEBUG
    public static var lastTopicTapAt: Date?
    public static var lastDetailLoadStart: Date?
    public static var lastDetailLoadEnd: Date?
    #else
    public static var lastTopicTapAt: Date? { get { nil } set {} }
    public static var lastDetailLoadStart: Date? { get { nil } set {} }
    public static var lastDetailLoadEnd: Date? { get { nil } set {} }
    #endif

    public static func elapsedMillis(from start: Date?, to end: Date? = Date()) -> Double? {
        guard let s = start, let e = end else { return nil }
        return e.timeIntervalSince(s) * 1000.0
    }
}
