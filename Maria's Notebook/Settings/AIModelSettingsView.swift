import SwiftUI

// MARK: - AI Model Option

/// Represents available AI model choices across the app.
enum AIModelOption: String, CaseIterable, Identifiable {
    case localFirstAuto = "local-first-auto"
    case appleOnDevice = "apple-on-device"
    case mlxLocal = "mlx-local"
    case ollamaLocal = "ollama-local"
    case claudeSonnet = "claude-sonnet-4-20250514"
    case claudeHaiku = "claude-haiku-4-20250414"
    case claudeOpus = "claude-opus-4-20250514"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .localFirstAuto: return "Local First (Auto)"
        case .appleOnDevice: return "Apple On-Device"
        case .mlxLocal: return "MLX Local"
        case .ollamaLocal: return "Ollama"
        case .claudeSonnet: return "Claude Sonnet 4"
        case .claudeHaiku: return "Claude Haiku 4"
        case .claudeOpus: return "Claude Opus 4"
        }
    }

    var subtitle: String {
        switch self {
        case .localFirstAuto: return "On-device first, Claude if needed"
        case .appleOnDevice: return "Apple Intelligence, private"
        case .mlxLocal: return "Open-source model on Apple Silicon"
        case .ollamaLocal: return "Local Ollama server"
        case .claudeSonnet: return "Balanced speed & quality"
        case .claudeHaiku: return "Fastest, less nuanced"
        case .claudeOpus: return "Most capable, slower"
        }
    }

    var iconName: String {
        switch self {
        case .localFirstAuto: return "arrow.triangle.branch"
        case .appleOnDevice: return "apple.logo"
        case .mlxLocal: return "cpu"
        case .ollamaLocal: return "server.rack"
        case .claudeSonnet: return "bolt.circle"
        case .claudeHaiku: return "hare"
        case .claudeOpus: return "brain"
        }
    }

    /// Whether this model requires a Claude API key.
    var requiresAPIKey: Bool {
        switch self {
        case .claudeSonnet, .claudeHaiku, .claudeOpus: return true
        default: return false
        }
    }

    /// Whether this model requires Apple Intelligence to be available.
    var requiresAppleIntelligence: Bool {
        self == .appleOnDevice || self == .localFirstAuto
    }

    /// Whether this is a local-only model option.
    var isLocal: Bool {
        switch self {
        case .appleOnDevice, .mlxLocal, .ollamaLocal, .localFirstAuto: return true
        default: return false
        }
    }
}

// MARK: - AI Feature Area

/// Represents each distinct area in the app where AI is used.
enum AIFeatureArea: String, CaseIterable, Identifiable {
    case chat
    case lessonPlanning
    case noteSuggestions
    case noteDrafting
    case databaseAnalysis

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chat: return "Ask AI"
        case .lessonPlanning: return "Lesson Planning"
        case .noteSuggestions: return "Note Suggestions"
        case .noteDrafting: return "Note Drafting"
        case .databaseAnalysis: return "Database Analysis"
        }
    }

    var description: String {
        switch self {
        case .chat: return "Conversational classroom assistant"
        case .lessonPlanning: return "Curriculum planning recommendations"
        case .noteSuggestions: return "Tag and scope suggestions for notes"
        case .noteDrafting: return "Drafting emails, reports, and summaries"
        case .databaseAnalysis: return "Full classroom data analysis and insights"
        }
    }

    var iconName: String {
        switch self {
        case .chat: return "bubble.left.and.text.bubble.right"
        case .lessonPlanning: return "list.clipboard"
        case .noteSuggestions: return "tag"
        case .noteDrafting: return "doc.richtext"
        case .databaseAnalysis: return "cylinder.split.1x2"
        }
    }

    /// The UserDefaults key for this area's model preference.
    var defaultsKey: String {
        switch self {
        case .chat: return UserDefaultsKeys.aiModelChat
        case .lessonPlanning: return UserDefaultsKeys.aiModelLessonPlanning
        case .noteSuggestions: return UserDefaultsKeys.aiModelNoteSuggestions
        case .noteDrafting: return UserDefaultsKeys.aiModelNoteDrafting
        case .databaseAnalysis: return UserDefaultsKeys.aiModelDatabaseAnalysis
        }
    }

    /// The default model for this area.
    var defaultModel: AIModelOption {
        switch self {
        case .chat: return .localFirstAuto
        case .lessonPlanning: return .claudeSonnet
        case .noteSuggestions: return .appleOnDevice
        case .noteDrafting: return .appleOnDevice
        case .databaseAnalysis: return .localFirstAuto
        }
    }
}

// MARK: - AI Model Settings View

/// Unified settings view for choosing AI models per feature area.
struct AIModelSettingsView: View {
    // Per-area model preferences
    @AppStorage(UserDefaultsKeys.aiModelChat)
    private var chatModel = AIFeatureArea.chat.defaultModel.rawValue

    @AppStorage(UserDefaultsKeys.aiModelLessonPlanning)
    private var lessonPlanningModel = AIFeatureArea.lessonPlanning.defaultModel.rawValue

    @AppStorage(UserDefaultsKeys.aiModelNoteSuggestions)
    private var noteSuggestionsModel = AIFeatureArea.noteSuggestions.defaultModel.rawValue

    @AppStorage(UserDefaultsKeys.aiModelNoteDrafting)
    private var noteDraftingModel = AIFeatureArea.noteDrafting.defaultModel.rawValue

    @AppStorage(UserDefaultsKeys.aiModelDatabaseAnalysis)
    private var databaseAnalysisModel = AIFeatureArea.databaseAnalysis.defaultModel.rawValue

    private var hasAPIKey: Bool {
        AnthropicAPIClient.hasAPIKey()
    }

    var body: some View {
        VStack(spacing: SettingsStyle.groupSpacing) {
            areaRow(
                area: .chat,
                selection: $chatModel
            )
            Divider()
            areaRow(
                area: .lessonPlanning,
                selection: $lessonPlanningModel
            )
            Divider()
            areaRow(
                area: .noteSuggestions,
                selection: $noteSuggestionsModel
            )
            Divider()
            areaRow(
                area: .noteDrafting,
                selection: $noteDraftingModel
            )
            Divider()
            areaRow(
                area: .databaseAnalysis,
                selection: $databaseAnalysisModel
            )

            if !hasAPIKey {
                apiKeyWarning
            }
        }
    }

    // MARK: - Area Row

    private func areaRow(area: AIFeatureArea, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: area.iconName)
                    .font(.subheadline)
                    .foregroundStyle(.tint)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(area.displayName)
                        .font(.subheadline.weight(.medium))
                    Text(area.description)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }

            Picker("Model", selection: selection) {
                ForEach(AIModelOption.allCases) { option in
                    HStack(spacing: 6) {
                        Image(systemName: option.iconName)
                        Text(option.displayName)
                    }
                    .tag(option.rawValue)
                }
            }
            .pickerStyle(.menu)

            // Show subtitle for the selected model
            if let selected = AIModelOption(rawValue: selection.wrappedValue) {
                HStack(spacing: 4) {
                    if selected.requiresAPIKey && !hasAPIKey {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.caption2)
                            .foregroundStyle(AppColors.warning)
                        Text("Requires API key")
                            .font(.caption2)
                            .foregroundStyle(AppColors.warning)
                    } else {
                        Text(selected.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - API Key Warning

    private var apiKeyWarning: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppColors.warning)
            Text("Claude models require an API key. Configure one below.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppColors.warning.opacity(0.08))
        )
    }
}

// MARK: - Helper to read the resolved model for a feature area

extension AIFeatureArea {
    /// Reads the currently selected model from UserDefaults for this area.
    func resolvedModel() -> AIModelOption {
        let stored = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
        return AIModelOption(rawValue: stored) ?? defaultModel
    }

    /// Returns the Claude model ID string if a Claude model is selected, or nil for on-device.
    func resolvedClaudeModelID() -> String? {
        let model = resolvedModel()
        guard model.requiresAPIKey else { return nil }
        return model.rawValue
    }
}
