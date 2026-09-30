// AIConfigurationResolver.swift
// Reads and encapsulates resolved lesson-planning AI settings from UserDefaults.

import Foundation

/// Encapsulates the resolved timeout, temperature, and system prompt for lesson
/// planning, reading from UserDefaults at initialisation time.
///
/// The three are developer controls, shown only in debug builds (Settings ›
/// Intelligence › Developer). A release build uses `LessonPlanningDefaults`, so a
/// value saved by an older build, or brought back by a restore, can't steer the
/// planner from somewhere the guide can no longer see or clear.
struct AIConfigurationResolver {
    let timeout: TimeInterval
    let temperature: Double
    let systemPrompt: String

    init(defaults: UserDefaults = .standard) {
        #if DEBUG
        let storedTimeout = defaults.integer(forKey: UserDefaultsKeys.lessonPlanningTimeout)
        self.timeout = TimeInterval(storedTimeout > 0 ? storedTimeout : LessonPlanningDefaults.timeout)
        if defaults.object(forKey: UserDefaultsKeys.lessonPlanningTemperature) != nil {
            self.temperature = min(max(defaults.double(forKey: UserDefaultsKeys.lessonPlanningTemperature), 0), 1)
        } else {
            self.temperature = LessonPlanningDefaults.temperature
        }
        let customPrompt = (defaults.string(forKey: UserDefaultsKeys.lessonPlanningSystemPrompt) ?? "").trimmed()
        #else
        self.timeout = TimeInterval(LessonPlanningDefaults.timeout)
        self.temperature = LessonPlanningDefaults.temperature
        let customPrompt = LessonPlanningDefaults.systemPrompt
        #endif
        let basePrompt = customPrompt.isEmpty ? AIPrompts.lessonPlanningAssistant : customPrompt
        self.systemPrompt = basePrompt + "\n\n" + AIPrompts.planningEvidenceGuardrails
    }
}
