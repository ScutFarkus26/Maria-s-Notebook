import Foundation

public enum PreferenceType: Sendable { case bool, int, double, string, data, date }

public struct PreferenceDefinition: Sendable {
    public let key: String
    public let type: PreferenceType
    public let defaultValue: PreferenceValueDTO?
    public let allowStringCoercion: Bool

    public init(key: String, type: PreferenceType, defaultValue: PreferenceValueDTO? = nil, allowStringCoercion: Bool = true) {
        self.key = key
        self.type = type
        self.defaultValue = defaultValue
        self.allowStringCoercion = allowStringCoercion
    }
}

public enum PreferenceRegistry {
    // Fill with real keys in use
    public static let definitions: [PreferenceDefinition] = [
        PreferenceDefinition(key: "StudentsView.presentNow.excludedNames", type: .string),
        PreferenceDefinition(key: "PlanningInbox.order", type: .string),
        PreferenceDefinition(key: "AttendanceEmail.enabled", type: .bool),
        PreferenceDefinition(key: "AttendanceEmail.to", type: .string),
        PreferenceDefinition(key: "AttendanceEmail.from", type: .string),
        PreferenceDefinition(key: "LessonAge.warningDays", type: .int),
        PreferenceDefinition(key: "LessonAge.overdueDays", type: .int),
        PreferenceDefinition(key: "LessonAge.freshColorHex", type: .string),
        PreferenceDefinition(key: "LessonAge.warningColorHex", type: .string),
        PreferenceDefinition(key: "LessonAge.overdueColorHex", type: .string),
        PreferenceDefinition(key: "WorkAge.warningDays", type: .int),
        PreferenceDefinition(key: "WorkAge.overdueDays", type: .int),
        PreferenceDefinition(key: "WorkAge.freshColorHex", type: .string),
        PreferenceDefinition(key: "WorkAge.warningColorHex", type: .string),
        PreferenceDefinition(key: "WorkAge.overdueColorHex", type: .string),
        PreferenceDefinition(key: "StudentDetailView.selectedChecklistSubject", type: .string),
        PreferenceDefinition(key: "lastBackupTimeInterval", type: .double),
        PreferenceDefinition(key: "Backup.encrypt", type: .bool)
        // Attendance locks handled dynamically: keys "Attendance.locked.<yyyy-MM-dd>"
    ]

    public static let byKey: [String: PreferenceDefinition] = Dictionary(uniqueKeysWithValues: definitions.map { ($0.key, $0) })

    public static let knownPrefixes: [String] = [
        "StudentsView.presentNow.",
        "PlanningInbox.",
        "AttendanceEmail.",
        "LessonAge.",
        "WorkAge.",
        "StudentDetailView.",
        "Backup.",
        "Attendance.locked."
    ]
}
