import Foundation
#if canImport(Testing)
import Testing

/// Helper for detecting memory leaks in Swift Testing.
///
/// Usage:
/// ```swift
/// @Test func noLeak() async {
///     let checker: LeakChecker<MyClass>
///     autoreleasepool {
///         let obj = MyClass()
///         checker = LeakChecker(obj)
///     }
///     #expect(!checker.hasLeak, "MyClass leaked")
/// }
/// ```
@available(macOS 14, iOS 17, *)
final class LeakChecker<T: AnyObject>: @unchecked Sendable {
    weak var instance: T?

    init(_ instance: T) {
        self.instance = instance
    }

    var hasLeak: Bool { instance != nil }
}
#endif
