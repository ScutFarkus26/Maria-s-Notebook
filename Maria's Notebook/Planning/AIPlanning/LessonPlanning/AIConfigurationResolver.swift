// AIConfigurationResolver.swift
// Reads and encapsulates resolved AI settings from UserDefaults for a given feature area.

import Foundation

/// Encapsulates the resolved AI model, timeout, temperature, and system prompt
/// for a single feature area, reading from UserDefaults at initialisation time.
struct AIConfigurationResolver {
    let model: String
    let timeout: TimeInterval
    let temperature: Double
    let systemPrompt: String

    init(for feature: AIFeatureArea) {
        let defaults = UserDefaults.standard
        self.model = feature.resolvedClaudeModelID()
            ?? defaults.string(forKey: UserDefaultsKeys.lessonPlanningModel)
                .flatMap { $0.isEmpty ? nil : $0 }
            ?? "claude-sonnet-4-20250514"
        let storedTimeout = defaults.integer(forKey: UserDefaultsKeys.lessonPlanningTimeout)
        self.timeout = storedTimeout > 0 ? TimeInterval(storedTimeout) : 120
        let storedTemp = defaults.double(forKey: UserDefaultsKeys.lessonPlanningTemperature)
        self.temperature = storedTemp > 0 ? storedTemp : 0.3
        let customPrompt = defaults.string(forKey: UserDefaultsKeys.lessonPlanningSystemPrompt) ?? ""
        self.systemPrompt = customPrompt.isEmpty ? AIPrompts.lessonPlanningAssistant : customPrompt
    }
}
