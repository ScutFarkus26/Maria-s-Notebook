import Foundation

public enum PreferenceType: Sendable { case bool, int, double, string, data, date }

public struct PreferenceDefinition: Sendable {
    public let key: String
    public let type: PreferenceType
    public let defaultValue: PreferenceValueDTO?
    public let allowStringCoercion: Bool

    public init(
        key: String,
        type: PreferenceType,
        defaultValue: PreferenceValueDTO? = nil,
        allowStringCoercion: Bool = true
    ) {
        self.key = key
        self.type = type
        self.defaultValue = defaultValue
        self.allowStringCoercion = allowStringCoercion
    }
}

public enum PreferenceRegistry {
    // Fill with real keys in use
    public static let definitions: [PreferenceDefinition] = [
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
        PreferenceDefinition(key: "lastBackupTimeInterval", type: .double),
        PreferenceDefinition(key: "Backup.encrypt", type: .bool),
        PreferenceDefinition(key: "General.showTestStudents", type: .bool, defaultValue: .bool(false)),
        PreferenceDefinition(
            key: "General.testStudentNames",
            type: .string,
            defaultValue: .string("Danny De Berry,Lil Dan D")
        ),
        PreferenceDefinition(key: "ReminderSync.syncListName", type: .string),
        PreferenceDefinition(key: "Backup.allowChecksumBypass", type: .bool),
        PreferenceDefinition(key: "PlanningRootView.mode", type: .string),
        PreferenceDefinition(key: "PresentationsCalendar.showWork", type: .bool, defaultValue: .bool(true)),
        PreferenceDefinition(key: "WorkCalendar.showPresentations", type: .bool, defaultValue: .bool(true)),
        PreferenceDefinition(key: "WorkAgenda.hideScheduled", type: .bool, defaultValue: .bool(false)),
        // Attendance locks handled dynamically: keys "Attendance.locked.<yyyy-MM-dd>"

        // AI Models (per-area)
        PreferenceDefinition(key: "AI.chatModel", type: .string, defaultValue: .string("local-first-auto")),
        PreferenceDefinition(
            key: "AI.lessonPlanningModel",
            type: .string,
            defaultValue: .string("claude-sonnet-4-20250514")
        ),
        PreferenceDefinition(key: "AI.backgroundTasksModel", type: .string, defaultValue: .string("local-first-auto")),

        // AI Providers
        PreferenceDefinition(key: "AI.ollamaBaseURL", type: .string, defaultValue: .string("http://localhost:11434")),
        PreferenceDefinition(key: "AI.ollamaModelName", type: .string, defaultValue: .string("llama3.2")),

        // CDLesson Planning
        PreferenceDefinition(
            key: "LessonPlanning.model",
            type: .string,
            defaultValue: .string("claude-sonnet-4-20250514")
        ),
        PreferenceDefinition(key: "LessonPlanning.timeout", type: .int, defaultValue: .int(120)),
        PreferenceDefinition(key: "LessonPlanning.systemPrompt", type: .string),
        PreferenceDefinition(key: "LessonPlanning.defaultDepth", type: .string, defaultValue: .string("standard")),
        PreferenceDefinition(key: "LessonPlanning.temperature", type: .double, defaultValue: .double(0.3))
    ]

    public static let byKey: [String: PreferenceDefinition] = definitions.toDictionary(by: \.key)

    public static let knownPrefixes: [String] = [
        "AI.",
        "General.",
        "PlanningInbox.",
        "AttendanceEmail.",
        "LessonAge.",
        "WorkAge.",
        "StudentDetailView.",
        "Backup.",
        "Attendance.locked.",
        "ReminderSync.",
        "LessonPlanning."
    ]
}
