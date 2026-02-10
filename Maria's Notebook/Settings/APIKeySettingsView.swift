//
//  APIKeySettingsView.swift
//  Maria's Notebook
//
//  Settings view for configuring Anthropic API key for Development Insights
//

import SwiftUI

// MARK: - URL Extension for Safe Known URLs

private extension URL {
    /// Creates a URL from a known-valid string, with proper error handling
    static func knownURL(_ string: String) -> URL {
        guard let url = URL(string: string) else {
            preconditionFailure("Invalid hardcoded URL: \(string). This is a programming error.")
        }
        return url
    }
}

struct APIKeySettingsView: View {
    @State private var apiKey: String = ""
    @State private var showingKey = false
    @State private var saveMessage: String?
    @State private var showingInfoSheet = false
    
    var body: some View {
        Form {
            Section {
                Text("Development Insights uses Claude AI to analyze student progress and generate detailed reports.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Section {
                HStack {
                    if showingKey {
                        TextField("sk-ant-api03-...", text: $apiKey)
                            .textContentType(.password)
                            #if os(iOS)
                            .autocapitalization(.none)
                            #endif
                            .autocorrectionDisabled()
                    } else {
                        SecureField("sk-ant-api03-...", text: $apiKey)
                            .textContentType(.password)
                            #if os(iOS)
                            .autocapitalization(.none)
                            #endif
                            .autocorrectionDisabled()
                    }
                    
                    Button(action: { showingKey.toggle() }) {
                        Image(systemName: showingKey ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                if let message = saveMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(message.contains("saved") ? .green : .red)
                }
            } header: {
                Text("API Key")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Get your API key from console.anthropic.com")
                    
                    if AnthropicAPIClient.hasAPIKey() {
                        Label("API key configured", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Label("No API key configured", systemImage: "xmark.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            
            Section {
                Button("Save API Key") {
                    saveAPIKey()
                }
                .disabled(apiKey.isEmpty)
                
                if AnthropicAPIClient.hasAPIKey() {
                    Button("Clear API Key", role: .destructive) {
                        clearAPIKey()
                    }
                }
            }
            
            Section {
                Button("How to Get an API Key") {
                    showingInfoSheet = true
                }
                
                Link("Open Anthropic Console", destination: .knownURL("https://console.anthropic.com/"))
                
                Link("View Pricing Information", destination: .knownURL("https://www.anthropic.com/pricing"))
            } header: {
                Text("Information")
            }
        }
        .navigationTitle("AI Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            loadCurrentKey()
        }
        .sheet(isPresented: $showingInfoSheet) {
            APIKeyInformationSheet()
        }
    }
    
    private func loadCurrentKey() {
        // Don't actually load the key for security - just check if one exists
        if AnthropicAPIClient.hasAPIKey() {
            apiKey = "••••••••••••••••••••"
        }
    }
    
    private func saveAPIKey() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard trimmedKey.hasPrefix("sk-ant-") else {
            saveMessage = "Invalid API key format"
            return
        }
        
        AnthropicAPIClient.saveAPIKey(trimmedKey)
        saveMessage = "API key saved successfully"

        // Clear message after 3 seconds
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            saveMessage = nil
        }
    }
    
    private func clearAPIKey() {
        AnthropicAPIClient.clearAPIKey()
        apiKey = ""
        saveMessage = "API key cleared"

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            saveMessage = nil
        }
    }
}

// MARK: - Information Sheet

struct APIKeyInformationSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Step 1
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Step 1: Create an Account", systemImage: "1.circle.fill")
                            .font(.headline)
                        
                        Text("Visit console.anthropic.com and sign up for a free account.")
                            .font(.body)
                        
                        Link("Open Anthropic Console →", destination: .knownURL("https://console.anthropic.com/"))
                            .font(.subheadline)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                    
                    // Step 2
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Step 2: Get API Key", systemImage: "2.circle.fill")
                            .font(.headline)
                        
                        Text("Navigate to 'API Keys' section and click 'Create Key'. Copy the key (starts with 'sk-ant-').")
                            .font(.body)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                    
                    // Step 3
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Step 3: Add to App", systemImage: "3.circle.fill")
                            .font(.headline)
                        
                        Text("Paste your API key in the settings above and tap 'Save API Key'.")
                            .font(.body)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                    
                    Divider()
                        .padding(.vertical)
                    
                    // Cost Information
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Cost Information", systemImage: "dollarsign.circle")
                            .font(.headline)
                        
                        Text("New accounts receive $5 in free credits.")
                            .font(.body)
                        
                        Text("Each student analysis costs approximately $0.01-0.02 (1-2 cents).")
                            .font(.body)
                        
                        Text("$5 credit = ~250-500 student analyses")
                            .font(.body)
                            .fontWeight(.semibold)
                        
                        Link("View Detailed Pricing →", destination: .knownURL("https://www.anthropic.com/pricing"))
                            .font(.subheadline)
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                    
                    // Privacy Note
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Privacy & Security", systemImage: "lock.shield")
                            .font(.headline)
                        
                        Text("Your API key is stored securely on your device. Student data is sent directly to Anthropic's secure servers for analysis and is not stored by Anthropic or any third parties.")
                            .font(.body)
                    }
                    .padding()
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle("Getting an API Key")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        APIKeySettingsView()
    }
}
