//
//  APIKeyProviderSettingsView.swift
//  Cosmic Daybook
//
//  One settings screen for every provider API key. `APIKeySettingsView`
//  (Anthropic) and `OpenAIAPIKeySettingsView` (OpenAI) are thin wrappers over
//  it — the screen only varies by its `APIKeyProvider` descriptor, which holds
//  every user-facing string plus the provider's `APIKeyStore`.
//

import SwiftUI
import OSLog

// MARK: - URL Extension for Safe Known URLs

extension URL {
    /// Creates a URL from a known-valid string, with proper error handling
    static func knownURL(_ string: String) -> URL {
        guard let url = URL(string: string) else {
            preconditionFailure("Invalid hardcoded URL: \(string). This is a programming error.")
        }
        return url
    }
}

// MARK: - Provider Descriptor

/// Everything one provider's key screen needs.
struct APIKeyProvider {
    /// A link shown in the screen's Information section.
    struct InfoLink: Identifiable {
        let title: String
        let url: URL
        var id: String { title }
    }

    let navigationTitle: String
    let introText: String
    let keySectionHeader: String
    let keyPlaceholder: String
    let helpText: String
    /// A pasted key must start with this before the screen will save it.
    let requiredSavePrefix: String
    let invalidFormatMessage: String
    /// Title of the button that opens `APIKeyInformationSheet`; nil hides it.
    let infoSheetButtonTitle: String?
    let links: [InfoLink]
    let informationFooter: String?
    let keyStore: APIKeyStore
}

extension APIKeyProvider {

    static let anthropic = APIKeyProvider(
        navigationTitle: "AI Settings",
        introText: "Development Insights uses Claude AI to analyze student progress and generate detailed reports.",
        keySectionHeader: "API Key",
        keyPlaceholder: "sk-ant-api03-...",
        helpText: "Get your API key from console.anthropic.com",
        requiredSavePrefix: "sk-ant-",
        invalidFormatMessage: "Invalid API key format",
        infoSheetButtonTitle: "How to Get an API Key",
        links: [
            InfoLink(title: "Open Anthropic Console", url: .knownURL("https://console.anthropic.com/")),
            InfoLink(title: "View Pricing Information", url: .knownURL("https://www.anthropic.com/pricing"))
        ],
        informationFooter: nil,
        keyStore: AnthropicAPIClient.keyStore
    )

    static let openAI = APIKeyProvider(
        navigationTitle: "OpenAI Settings",
        introText: "Story cover generation uses OpenAI's gpt-image-1 to render illustrated covers.",
        keySectionHeader: "OpenAI API Key",
        keyPlaceholder: "sk-...",
        helpText: "Get your API key from platform.openai.com",
        requiredSavePrefix: "sk-",
        invalidFormatMessage: "Invalid API key format (should start with sk-)",
        infoSheetButtonTitle: nil,
        links: [
            InfoLink(title: "Open OpenAI Platform", url: .knownURL("https://platform.openai.com/api-keys")),
            InfoLink(title: "View Pricing", url: .knownURL("https://openai.com/api/pricing/"))
        ],
        informationFooter: "Cover generation runs at \"low\" quality (~$0.011 per portrait cover).",
        keyStore: OpenAIAPIClient.keyStore
    )
}

// MARK: - Shared Screen

struct APIKeyProviderSettingsView: View {
    private static let logger = Logger.settings

    let provider: APIKeyProvider

    @State private var apiKey: String = ""
    @State private var showingKey = false
    @State private var saveMessage: String?
    @State private var showingInfoSheet = false

    var body: some View {
        Form {
            Section {
                Text(provider.introText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            keySection

            Section {
                Button("Save API Key") {
                    saveAPIKey()
                }
                .disabled(apiKey.isEmpty)

                if provider.keyStore.hasKey() {
                    Button("Clear API Key", role: .destructive) {
                        clearAPIKey()
                    }
                }
            }

            informationSection
        }
        .navigationTitle(provider.navigationTitle)
        .inlineNavigationTitle()
        .onAppear {
            loadCurrentKey()
        }
        .sheet(isPresented: $showingInfoSheet) {
            APIKeyInformationSheet()
        }
    }

    private var keySection: some View {
        Section {
            HStack {
                if showingKey {
                    TextField(provider.keyPlaceholder, text: $apiKey)
                        .textContentType(.password)
                        #if os(iOS)
                        .autocapitalization(.none)
                        #endif
                        .autocorrectionDisabled()
                } else {
                    SecureField(provider.keyPlaceholder, text: $apiKey)
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
            Text(provider.keySectionHeader)
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text(provider.helpText)

                if provider.keyStore.hasKey() {
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
    }

    private var informationSection: some View {
        Section {
            if let infoSheetButtonTitle = provider.infoSheetButtonTitle {
                Button(infoSheetButtonTitle) {
                    showingInfoSheet = true
                }
            }

            ForEach(provider.links) { link in
                Link(link.title, destination: link.url)
            }
        } header: {
            Text("Information")
        } footer: {
            if let informationFooter = provider.informationFooter {
                Text(informationFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func loadCurrentKey() {
        // Don't actually load the key for security - just check if one exists
        if provider.keyStore.hasKey() {
            apiKey = "••••••••••••••••••••"
        }
    }

    private func saveAPIKey() {
        let trimmedKey = apiKey.trimmed()

        guard trimmedKey.hasPrefix(provider.requiredSavePrefix) else {
            saveMessage = provider.invalidFormatMessage
            return
        }

        provider.keyStore.save(trimmedKey)
        saveMessage = "API key saved successfully"
        dismissSaveMessageAfterDelay()
    }

    private func clearAPIKey() {
        provider.keyStore.clear()
        apiKey = ""
        saveMessage = "API key cleared"
        dismissSaveMessageAfterDelay()
    }

    /// Clear message after 3 seconds
    private func dismissSaveMessageAfterDelay() {
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
