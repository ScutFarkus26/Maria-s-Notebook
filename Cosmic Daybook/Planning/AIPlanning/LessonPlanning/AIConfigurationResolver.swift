// AIConfigurationResolver.swift
// Reads and encapsulates resolved lesson-planning AI settings from UserDefaults.

import Foundation

/// Encapsulates the resolved timeout, temperature, and system prompt for lesson
/// planning, reading from UserDefaults at initialisation time.
struct AIConfigurationResolver {
    let timeout: TimeInterval
    let temperature: Double
    let systemPrompt: String

    init() {
        let defaults = UserDefaults.standard
        let storedTimeout = defaults.integer(forKey: UserDefaultsKeys.lessonPlanningTimeout)
        self.timeout = storedTimeout > 0 ? TimeInterval(storedTimeout) : 120
        if defaults.object(forKey: UserDefaultsKeys.lessonPlanningTemperature) != nil {
            self.temperature = min(max(defaults.double(forKey: UserDefaultsKeys.lessonPlanningTemperature), 0), 1)
        } else {
            self.temperature = 0.3
        }
        let customPrompt = (defaults.string(forKey: UserDefaultsKeys.lessonPlanningSystemPrompt) ?? "").trimmed()
        let basePrompt = customPrompt.isEmpty ? AIPrompts.lessonPlanningAssistant : customPrompt
        self.systemPrompt = basePrompt + "\n\n" + AIPrompts.planningEvidenceGuardrails
    }
}
