import Foundation

@available(*, deprecated, message: "WorkCheckInDefaults was tied to legacy WorkModel. Use WorkContract scheduling instead.")
struct WorkCheckInDefaults {
    static func daysOffset(for type: Any) -> Int { 2 }
    static func setDaysOffset(_ days: Int, for type: Any) { /* no-op */ }
}
