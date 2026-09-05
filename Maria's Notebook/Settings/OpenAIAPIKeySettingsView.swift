//
//  OpenAIAPIKeySettingsView.swift
//  Maria's Notebook
//
//  Settings view for configuring an OpenAI API key (used for story cover generation
//  via gpt-image-1). Mirrors `APIKeySettingsView` for the Anthropic key.
//

import SwiftUI
import OSLog

private extension URL {
    static func knownURL(_ string: String) -> URL {
        guard let url = URL(string: string) else {
            preconditionFailure("Invalid hardcoded URL: \(string)")
        }
        return url
    }
}

struct OpenAIAPIKeySettingsView: View {
    private static let logger = Logger.settings
    @State private var apiKey: String = ""
    @State private var showingKey = false
    @State private var saveMessage: String?

    var body: some View {
        Form {
            Section {
                Text("Story cover generation uses OpenAI's gpt-image-1 to render illustrated covers.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    if showingKey {
                        TextField("sk-...", text: $apiKey)
                            .textContentType(.password)
                            #if os(iOS)
                            .autocapitalization(.none)
                            #endif
                            .autocorrectionDisabled()
                    } else {
                        SecureField("sk-...", text: $apiKey)
                            .textContentType(.password)
                            #if os(iOS)
                            .autocapitalization(.none)
                            #endif
                            .autocorrectionDisabled()
                    }

                    Button(action: { showingKey.toggle() }, label: {
                        Image(systemName: showingKey ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    })
                    .buttonStyle(.plain)
                }

                if let message = saveMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(message.contains("saved") ? .green : .red)
                }
            } header: {
                Text("OpenAI API Key")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Get your API key from platform.openai.com")

                    if OpenAIAPIClient.hasAPIKey() {
                        Label("API key configured", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(AppColors.success)
                    } else {
                        Label("No API key configured", systemImage: "xmark.circle")
                            .font(.caption)
                            .foregroundStyle(AppColors.warning)
                    }
                }
            }

            Section {
                Button("Save API Key") {
                    saveAPIKey()
                }
                .disabled(apiKey.isEmpty)

                if OpenAIAPIClient.hasAPIKey() {
                    Button("Clear API Key", role: .destructive) {
                        clearAPIKey()
                    }
                }
            }

            Section {
                Link("Open OpenAI Platform", destination: .knownURL("https://platform.openai.com/api-keys"))
                Link("View Pricing", destination: .knownURL("https://openai.com/api/pricing/"))
            } header: {
                Text("Information")
            } footer: {
                Text("Cover generation runs at \"low\" quality (~$0.011 per portrait cover).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("OpenAI Settings")
        .inlineNavigationTitle()
        .onAppear { loadCurrentKey() }
    }

    private func loadCurrentKey() {
        // Don't actually expose the key — just indicate one exists.
        if OpenAIAPIClient.hasAPIKey() {
            apiKey = "••••••••••••••••••••"
        }
    }

    private func saveAPIKey() {
        let trimmedKey = apiKey.trimmed()
        guard trimmedKey.hasPrefix("sk-") else {
            saveMessage = "Invalid API key format (should start with sk-)"
            return
        }
        OpenAIAPIClient.saveAPIKey(trimmedKey)
        saveMessage = "API key saved successfully"

        Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                Self.logger.warning("Failed to sleep for message dismiss: \(error, privacy: .public)")
            }
            saveMessage = nil
        }
    }

    private func clearAPIKey() {
        OpenAIAPIClient.clearAPIKey()
        apiKey = ""
        saveMessage = "API key cleared"

        Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                Self.logger.warning("Failed to sleep for message dismiss: \(error, privacy: .public)")
            }
            saveMessage = nil
        }
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct OpenAIAPIKeySettingsViewPreview: View {
    var body: some View {
        NavigationStack { OpenAIAPIKeySettingsView() }
    }
}

#Preview {
    OpenAIAPIKeySettingsViewPreview()
}
