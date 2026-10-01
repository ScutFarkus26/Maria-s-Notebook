import SwiftUI

// MARK: - Defaults

/// Lesson planning's settings as they start, and as Reset puts them back.
/// `AIConfigurationResolver` falls back to the same values when nothing is stored.
enum LessonPlanningDefaults {
    /// Seconds to wait for a planning response.
    static let timeout = 120
    static let depth: PlanningDepth = .standard
    static let temperature = 0.3
    /// Empty means the built-in prompt (`AIPrompts.lessonPlanningAssistant`).
    static let systemPrompt = ""
}

// MARK: - Lesson Planning

/// Settings › Intelligence › Lesson planning: how much work the planning
/// assistant does by default. The prompt, temperature and timeout are
/// developer controls, in `LessonPlanningDeveloperSettingsView` (debug builds).
struct LessonPlanningSettingsView: View {
    @AppStorage(UserDefaultsKeys.lessonPlanningDefaultDepth)
    private var defaultDepth: PlanningDepth = LessonPlanningDefaults.depth

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            #if os(macOS)
            LabeledContent("Default depth") {
                depthPicker
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
            }
            #else
            Text("Default depth")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            depthPicker
                .pickerStyle(.segmented)
            #endif

            Text(defaultDepth.description)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var depthPicker: some View {
        // A stored "Deep" (no longer offered) shows as Standard, which is how it plans.
        Picker("Default depth", selection: Binding(get: { defaultDepth.effective }, set: { defaultDepth = $0 })) {
            ForEach(PlanningDepth.offered) { depth in
                Text(depth.displayName).tag(depth)
            }
        }
    }
}

#if DEBUG
/// The planning assistant's prompt, temperature and request timeout. Not
/// teacher settings: debug builds show them in Settings › Intelligence ›
/// Developer, and release builds use `AIConfigurationResolver`'s defaults.
struct LessonPlanningDeveloperSettingsView: View {
    @AppStorage(UserDefaultsKeys.lessonPlanningTimeout) private var timeout = LessonPlanningDefaults.timeout
    @AppStorage(UserDefaultsKeys.lessonPlanningDefaultDepth)
    private var defaultDepth: PlanningDepth = LessonPlanningDefaults.depth
    @AppStorage(UserDefaultsKeys.lessonPlanningTemperature) private var temperature = LessonPlanningDefaults.temperature
    @AppStorage(UserDefaultsKeys.lessonPlanningSystemPrompt)
    private var customSystemPrompt = LessonPlanningDefaults.systemPrompt

    @State private var isPromptExpanded = false
    @State private var isConfirmingClearPrompt = false
    @State private var isConfirmingReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsStyle.groupSpacing) {
            promptSection
            Divider()
            advancedSection
            resetSection
        }
    }

    // MARK: - System Prompt

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Button {
                adaptiveWithAnimation(.easeInOut(duration: 0.2)) {
                    isPromptExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("System prompt")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isPromptExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if isPromptExpanded {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                    Text("Override the default Montessori planning prompt. Leave empty to use the built-in prompt.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    TextEditor(text: $customSystemPrompt)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 120, maxHeight: 240)
                        .padding(AppTheme.Spacing.verySmall)
                        .surface(
                            UIConstants.CornerRadius.medium,
                            fill: Color.primary.opacity(UIConstants.OpacityConstants.trace),
                            stroke: Color.primary.opacity(UIConstants.OpacityConstants.light),
                            style: .continuous
                        )

                    if customSystemPrompt.isEmpty {
                        Text("Using default prompt (\(AIPrompts.lessonPlanningAssistant.count) characters)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        HStack {
                            Text("Custom prompt: \(customSystemPrompt.count) characters")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Clear") {
                                isConfirmingClearPrompt = true
                            }
                            .font(.caption2)
                            .foregroundStyle(AppColors.destructive)
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            "Clear the custom prompt?",
            isPresented: $isConfirmingClearPrompt,
            titleVisibility: .visible
        ) {
            Button("Clear prompt", role: .destructive) {
                customSystemPrompt = LessonPlanningDefaults.systemPrompt
            }
        } message: {
            Text("Lesson planning goes back to the built-in prompt.")
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            #if os(macOS)
            LabeledContent("Temperature") {
                HStack(spacing: AppTheme.Spacing.small) {
                    Slider(value: $temperature, in: 0.0...1.0, step: 0.1)
                        .frame(minWidth: 140, idealWidth: 180, maxWidth: 220)
                    Text(String(format: "%.1f", temperature))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)
                }
            }
            #else
            temperatureControl
            #endif
            Text("Lower values produce more focused, deterministic responses. Higher values add variety.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Divider()

            #if os(macOS)
            LabeledContent("Request timeout") {
                HStack(spacing: AppTheme.Spacing.small) {
                    timeoutSlider
                        .frame(minWidth: 140, idealWidth: 180, maxWidth: 220)
                    Text("\(timeout)s")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)
                }
            }
            #else
            timeoutControl
            #endif
            Text("How long to wait for a response before timing out. Increase if you see timeout errors.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var timeoutSlider: some View {
        Slider(value: Binding(
            get: { Double(timeout) },
            set: { timeout = Int($0) }
        ), in: 30...300, step: 30)
    }

    #if os(iOS)
    private var temperatureControl: some View {
        VStack(spacing: AppTheme.Spacing.small) {
            HStack {
                Text("Temperature")
                    .font(.subheadline)
                Spacer()
                Text(String(format: "%.1f", temperature))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $temperature, in: 0.0...1.0, step: 0.1)
        }
    }

    private var timeoutControl: some View {
        VStack(spacing: AppTheme.Spacing.small) {
            HStack {
                Text("Request timeout")
                    .font(.subheadline)
                Spacer()
                Text("\(timeout)s")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            timeoutSlider
        }
    }
    #endif

    // MARK: - Reset

    private var resetSection: some View {
        HStack {
            Spacer()
            Button("Reset to defaults") {
                isConfirmingReset = true
            }
            .font(.caption)
            .foregroundStyle(AppColors.destructive)
            Spacer()
        }
        .confirmationDialog(
            "Reset lesson planning to its defaults?",
            isPresented: $isConfirmingReset,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                timeout = LessonPlanningDefaults.timeout
                defaultDepth = LessonPlanningDefaults.depth
                temperature = LessonPlanningDefaults.temperature
                customSystemPrompt = LessonPlanningDefaults.systemPrompt
            }
        } message: {
            Text("The default depth, prompt, temperature and timeout all go back to how they started.")
        }
    }
}
#endif
