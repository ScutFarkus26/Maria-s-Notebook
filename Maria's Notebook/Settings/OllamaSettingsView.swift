import SwiftUI

/// Settings view for configuring the Ollama local LLM server connection.
struct OllamaSettingsView: View {
    @Environment(\.dependencies) private var dependencies
    @AppStorage(UserDefaultsKeys.ollamaBaseURL) private var baseURLString = "http://localhost:11434"
    @AppStorage(UserDefaultsKeys.ollamaModelName) private var selectedModel = "llama3.2"

    @State private var isConnected = false
    @State private var availableModels: [OllamaModel] = []
    @State private var isTesting = false
    @State private var errorMessage: String?

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
            gettingStartedSection
        }
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

    // MARK: - Getting Started

    private var gettingStartedSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
            Text("Getting Started")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("1. Install Ollama from ollama.com")
                Text("2. Open Ollama to start the server")
                Text("3. Pull a model: ollama pull llama3.2")
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

    private func testAndApplyURL() async {
        isTesting = true
        await refreshConnection()
        isTesting = false
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
