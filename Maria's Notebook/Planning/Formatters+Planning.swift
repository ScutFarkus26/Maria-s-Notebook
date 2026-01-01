import Foundation

enum Formatters {
    static let dayName: DateFormatter = {
        let df = DateFormatter()
        df.setLocalizedDateFormatFromTemplate("EEE")
        return df
    }()
    static let dayNumber: DateFormatter = {
        let df = DateFormatter()
        df.setLocalizedDateFormatFromTemplate("d")
        return df
    }()
    static let weekRange: DateFormatter = {
        let df = DateFormatter()
        df.setLocalizedDateFormatFromTemplate("MMM d")
        return df
    }()
}
