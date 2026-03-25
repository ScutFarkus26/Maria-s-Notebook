// swiftlint:disable file_length
import SwiftUI

// Settings view for configuring the Ollama local LLM server connection.
// swiftlint:disable:next type_body_length
struct OllamaSettingsView: View {
    @Environment(\.dependencies) private var dependencies
    @AppStorage(UserDefaultsKeys.ollamaBaseURL) private var baseURLString = "http://localhost:11434"
    @AppStorage(UserDefaultsKeys.ollamaModelName) private var selectedModel = "llama3.2"

    @State private var isConnected = false
    @State private var availableModels: [OllamaModel] = []
    @State private var isTesting = false
    @State private var errorMessage: String?

    // Pull state
    @State private var isPulling = false
    @State private var pullModelName = ""
    @State private var pullProgress: Double = 0
    @State private var pullStatusText = ""
    @State private var pullError: String?
    @State private var showCustomModelField = false
    @State private var customModelName = ""

    private var ollamaClient: OllamaClient {
        dependencies.aiRouter.ollamaClient
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsStyle.groupSpacing) {
            connectionStatus
            Divider()
            serverURLSection
            Divider()
            modelPickerSection
            Divider()
            installModelsSection
            Divider()
            gettingStartedSection
        }
        .onChange(of: baseURLString) { _, _ in SettingsCategory.markModified(.aiFeatures) }
        .onChange(of: selectedModel) { _, _ in SettingsCategory.markModified(.aiFeatures) }
    }

    // MARK: - Connection Status

    private var connectionStatus: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Image(systemName: isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isConnected ? AppColors.success : AppColors.warning)
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 2) {
                if isConnected {
                    Text("Connected")
                        .font(AppTheme.ScaledFont.bodySemibold)
                        .foregroundStyle(AppColors.success)
                    if !availableModels.isEmpty {
                        Text("\(availableModels.count) model\(availableModels.count == 1 ? "" : "s") available")
                            .font(AppTheme.ScaledFont.captionSmall)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Not Connected")
                        .font(AppTheme.ScaledFont.bodySemibold)
                        .foregroundStyle(AppColors.warning)
                    if let error = errorMessage {
                        Text(error)
                            .font(AppTheme.ScaledFont.captionSmall)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .task {
            await refreshConnection()
        }
    }

    // MARK: - Server URL

    private var serverURLSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text("Server URL")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)

            HStack(spacing: AppTheme.Spacing.small) {
                TextField("http://localhost:11434", text: $baseURLString)
                    .textFieldStyle(.plain)
                    .font(AppTheme.ScaledFont.body)
                    .padding(.horizontal, AppTheme.Spacing.compact)
                    .padding(.vertical, AppTheme.Spacing.small)
                    .background(Color.secondary.opacity(UIConstants.OpacityConstants.veryFaint))
                    .clipShape(RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium))
                    #if !os(macOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()

                Button {
                    Task { await testAndApplyURL() }
                } label: {
                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Test")
                            .font(AppTheme.ScaledFont.captionSemibold)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isTesting)
            }
        }
    }

    // MARK: - Model Picker

    private var modelPickerSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text("Active Model")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)

            if isConnected && !availableModels.isEmpty {
                Picker("Model", selection: $selectedModel) {
                    ForEach(availableModels) { model in
                        HStack {
                            Text(model.name)
                            Spacer()
                            Text(formatSize(model.size))
                                .font(AppTheme.ScaledFont.captionSmall)
                                .foregroundStyle(.secondary)
                        }
                        .tag(model.name)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedModel) {
                    ollamaClient.modelName = selectedModel
                }
            } else {
                Text("Connect to Ollama to see available models")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Install Models

    private var installModelsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            Text("Install Models")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)

            ForEach(OllamaModelCatalog.recommended) { model in
                catalogModelRow(model)
                if model.id != OllamaModelCatalog.recommended.last?.id {
                    Divider()
                }
            }

            if isConnected {
                Divider()
                customModelPullSection
            }
        }
    }

    @ViewBuilder
    // swiftlint:disable:next function_body_length
    private func catalogModelRow(_ model: OllamaModelCatalog) -> some View {
        let isInstalled = availableModels.contains { $0.name.hasPrefix(model.id) }
        let isCurrentlyPulling = isPulling && pullModelName == model.id
        let hasError = !isPulling && pullError != nil && pullModelName == model.id

        VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
            // Model info row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: AppTheme.Spacing.small) {
                        Text(model.name)
                            .font(AppTheme.ScaledFont.bodySemibold)

                        Text(model.parameterCount)
                            .font(AppTheme.ScaledFont.captionSmallSemibold)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, AppTheme.Spacing.verySmall)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(UIConstants.OpacityConstants.veryFaint))
                            .clipShape(Capsule())

                        if isInstalled {
                            Text("Installed")
                                .font(AppTheme.ScaledFont.captionSmallSemibold)
                                .foregroundStyle(AppColors.success)
                                .padding(.horizontal, AppTheme.Spacing.verySmall)
                                .padding(.vertical, 1)
                                .background(AppColors.success.opacity(UIConstants.OpacityConstants.light))
                                .clipShape(Capsule())
                        }
                    }

                    Text(model.description)
                        .font(AppTheme.ScaledFont.captionSmall)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }

                Spacer()

                Text(String(format: "%.1f GB", model.sizeGB))
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
            }

            // Progress bar while pulling
            if isCurrentlyPulling {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
                    ProgressView(value: pullProgress)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)

                    HStack {
                        Text(pullStatusText.isEmpty ? "Connecting..." : pullStatusText)
                            .font(AppTheme.ScaledFont.captionSmall)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int(pullProgress * 100))%")
                            .font(AppTheme.ScaledFont.captionSmallSemibold)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, AppTheme.Spacing.xsmall)
            }

            // Error message inline on this row
            if hasError, let error = pullError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(AppColors.destructive)
                    .lineLimit(2)
                    .padding(.top, AppTheme.Spacing.xsmall)
            }

            // Install / Retry button
            if !isInstalled && !isCurrentlyPulling {
                Button {
                    Task { await performPull(name: model.id) }
                } label: {
                    Label(
                        hasError ? "Retry" : "Install",
                        systemImage: hasError ? "arrow.clockwise" : "arrow.down.circle"
                    )
                    .font(AppTheme.ScaledFont.captionSemibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(hasError ? AppColors.warning : .accentColor)
                .controlSize(.small)
                .disabled(isPulling)
                .padding(.top, AppTheme.Spacing.xsmall)
            }
        }
        .padding(.vertical, AppTheme.Spacing.xsmall)
    }

    // MARK: - Custom Model Pull

    private var customModelPullSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Button {
                _ = adaptiveWithAnimation(.easeInOut(duration: 0.25)) {
                    showCustomModelField.toggle()
                }
            } label: {
                HStack(spacing: AppTheme.Spacing.small) {
                    Image(systemName: "plus.circle")
                    Text("Install Other Model")
                        .font(AppTheme.ScaledFont.caption)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showCustomModelField ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if showCustomModelField {
                HStack(spacing: AppTheme.Spacing.small) {
                    TextField("Model name (e.g. codellama:7b)", text: $customModelName)
                        .textFieldStyle(.plain)
                        .font(AppTheme.ScaledFont.body)
                        .padding(.horizontal, AppTheme.Spacing.compact)
                        .padding(.vertical, AppTheme.Spacing.small)
                        .background(Color.secondary.opacity(UIConstants.OpacityConstants.veryFaint))
                        .clipShape(RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium))
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()

                    Button {
                        let name = customModelName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        Task { await performPull(name: name) }
                    } label: {
                        if isPulling && pullModelName == customModelName.trimmingCharacters(in: .whitespaces) {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Pull")
                                .font(AppTheme.ScaledFont.captionSemibold)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isPulling || customModelName.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if isPulling && pullModelName == customModelName.trimmingCharacters(in: .whitespaces) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
                        ProgressView(value: pullProgress)
                            .progressViewStyle(.linear)
                            .tint(.accentColor)

                        HStack {
                            Text(pullStatusText.isEmpty ? "Connecting..." : pullStatusText)
                                .font(AppTheme.ScaledFont.captionSmall)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text("\(Int(pullProgress * 100))%")
                                .font(AppTheme.ScaledFont.captionSmallSemibold)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Getting Started

    private var gettingStartedSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
            Text("Getting Started")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("1. Install Ollama from ollama.com")
                Text("2. Open Ollama to start the server")
                Text("3. Install a model using the section above")
            }
            .font(AppTheme.ScaledFont.captionSmall)
            .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Actions

    private func refreshConnection() async {
        guard let url = URL(string: baseURLString) else {
            isConnected = false
            errorMessage = "Invalid URL"
            return
        }
        ollamaClient.updateBaseURL(url)
        ollamaClient.modelName = selectedModel

        do {
            let models = try await ollamaClient.listModels()
            isConnected = true
            availableModels = models
            errorMessage = nil
        } catch {
            isConnected = false
            availableModels = []
            errorMessage = "Cannot reach server"
        }
    }

    func testAndApplyURL() async {
        isTesting = true
        await refreshConnection()
        isTesting = false
    }

    private func performPull(name: String) async {
        // Reset state for this pull
        isPulling = true
        pullModelName = name
        pullProgress = 0
        pullStatusText = ""
        pullError = nil

        // Ensure base URL is set before pulling
        if let url = URL(string: baseURLString) {
            ollamaClient.updateBaseURL(url)
        }

        // Iterate the AsyncThrowingStream directly on the main actor
        // so all @State updates happen synchronously here.
        let stream = ollamaClient.pullModel(name: name)

        do {
            for try await progress in stream {
                pullStatusText = progress.status
                if let fraction = progress.fractionCompleted {
                    pullProgress = fraction
                }
            }

            // Stream finished (success) — refresh the model list
            pullStatusText = "Complete!"
            pullProgress = 1.0
            await refreshConnection()

            // Brief pause to show 100% before clearing
            try? await Task.sleep(nanoseconds: UIConstants.TimingDelay.toast)

            // Clear pull state on success
            pullModelName = ""
            pullError = nil
        } catch {
            // Keep pullModelName set so the error shows on the correct row
            pullError = error.localizedDescription
        }

        isPulling = false
        pullProgress = 0
        pullStatusText = ""
    }

    // MARK: - Helpers

    private func formatSize(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        } else {
            let mb = Double(bytes) / 1_048_576
            return String(format: "%.0f MB", mb)
        }
    }
}
