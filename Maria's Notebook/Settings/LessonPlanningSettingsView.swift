import SwiftUI

/// Settings view for configuring the AI lesson planning assistant.
/// Model selection has moved to the AI Models section above.
struct LessonPlanningSettingsView: View {
    @AppStorage(UserDefaultsKeys.lessonPlanningTimeout) private var timeout = 120
    @AppStorage(UserDefaultsKeys.lessonPlanningDefaultDepth) private var defaultDepth = "standard"
    @AppStorage(UserDefaultsKeys.lessonPlanningTemperature) private var temperature = 0.3
    @AppStorage(UserDefaultsKeys.lessonPlanningSystemPrompt) private var customSystemPrompt = ""

    @State private var isPromptExpanded = false

    private let depthOptions = [
        ("quick", "Quick", "Fast suggestions based on readiness"),
        ("standard", "Standard", "Scheduled plan with grouping suggestions"),
        ("deep", "Deep", "Full weekly optimization across all students")
    ]

    var body: some View {
        VStack(spacing: SettingsStyle.groupSpacing) {
            planningSection
            promptSection
            advancedSection
            resetSection
        }
        .onChange(of: timeout) { _, _ in SettingsCategory.markModified(.aiFeatures) }
        .onChange(of: defaultDepth) { _, _ in SettingsCategory.markModified(.aiFeatures) }
        .onChange(of: temperature) { _, _ in SettingsCategory.markModified(.aiFeatures) }
        .onChange(of: customSystemPrompt) { _, _ in SettingsCategory.markModified(.aiFeatures) }
    }

    // MARK: - Planning Defaults

    private var planningSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Default Depth")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("Depth", selection: $defaultDepth) {
                ForEach(depthOptions, id: \.0) { value, label, _ in
                    Text(label).tag(value)
                }
            }
            .pickerStyle(.segmented)

            if let selected = depthOptions.first(where: { $0.0 == defaultDepth }) {
                Text(selected.2)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - System Prompt

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                adaptiveWithAnimation(.easeInOut(duration: 0.2)) {
                    isPromptExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("System Prompt")
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
                VStack(alignment: .leading, spacing: 6) {
                    Text("Override the default Montessori planning prompt. Leave empty to use the built-in prompt.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    TextEditor(text: $customSystemPrompt)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 120, maxHeight: 240)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.primary.opacity(UIConstants.OpacityConstants.light))
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
                                customSystemPrompt = ""
                            }
                            .font(.caption2)
                            .foregroundStyle(AppColors.destructive)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Advanced")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack {
                Text("Temperature")
                    .font(.subheadline)
                Spacer()
                Text(String(format: "%.1f", temperature))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $temperature, in: 0.0...1.0, step: 0.1)
            Text("Lower values produce more focused, deterministic responses. Higher values add variety.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Divider()

            HStack {
                Text("Request Timeout")
                    .font(.subheadline)
                Spacer()
                Text("\(timeout)s")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(
                get: { Double(timeout) },
                set: { timeout = Int($0) }
            ), in: 30...300, step: 30)
            Text("How long to wait for a response before timing out. Increase if you see timeout errors.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Reset

    private var resetSection: some View {
        HStack {
            Spacer()
            Button("Reset to Defaults") {
                timeout = 120
                defaultDepth = "standard"
                temperature = 0.3
                customSystemPrompt = ""
            }
            .font(.caption)
            .foregroundStyle(AppColors.destructive)
            Spacer()
        }
    }
}
