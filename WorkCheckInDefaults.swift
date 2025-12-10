import Foundation

struct WorkCheckInDefaults {
    private static let researchKey = "WorkCheckInDefaults.researchDays"
    private static let followUpKey = "WorkCheckInDefaults.followUpDays"
    private static let practiceKey = "WorkCheckInDefaults.practiceDays"

    /// Returns the default day offset for the given work type. If not set, returns 2.
    static func daysOffset(for type: WorkModel.WorkType) -> Int {
        let defaults = UserDefaults.standard
        switch type {
        case .research:
            return defaults.object(forKey: researchKey) as? Int ?? 2
        case .followUp:
            return defaults.object(forKey: followUpKey) as? Int ?? 2
        case .practice:
            return defaults.object(forKey: practiceKey) as? Int ?? 2
        }
    }

    /// Set the default day offset for a work type. Values <= 0 will be clamped to 0.
    static func setDaysOffset(_ days: Int, for type: WorkModel.WorkType) {
        let value = max(0, days)
        let defaults = UserDefaults.standard
        switch type {
        case .research:
            defaults.set(value, forKey: researchKey)
        case .followUp:
            defaults.set(value, forKey: followUpKey)
        case .practice:
            defaults.set(value, forKey: practiceKey)
        }
    }
}
