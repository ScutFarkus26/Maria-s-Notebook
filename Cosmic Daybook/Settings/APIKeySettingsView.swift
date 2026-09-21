//
//  APIKeySettingsView.swift
//  Cosmic Daybook
//
//  Settings view for configuring Anthropic API key for Development Insights
//

import SwiftUI

/// Anthropic key screen. The screen itself is `APIKeyProviderSettingsView`;
/// this wrapper keeps the name its callers already use.
struct APIKeySettingsView: View {
    var body: some View {
        APIKeyProviderSettingsView(provider: .anthropic)
    }
}

// MARK: - Information Sheet

struct APIKeyInformationSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    stepsSection
                    Divider().padding(.vertical)
                    costSection
                    privacySection
                }
                .padding()
            }
            .navigationTitle("Getting an API Key")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var stepsSection: some View {
        Group {
            infoCard(color: .blue) {
                Label("Step 1: Create an Account", systemImage: "1.circle.fill")
                    .font(.headline)
                Text("Visit console.anthropic.com and sign up for a free account.")
                    .font(.body)
                Link("Open Anthropic Console →", destination: .knownURL("https://console.anthropic.com/"))
                    .font(.subheadline)
            }

            infoCard(color: .blue) {
                Label("Step 2: Get API Key", systemImage: "2.circle.fill")
                    .font(.headline)
                Text(
                    "Navigate to 'API Keys' section and click 'Create Key'."
                    + " Copy the key (starts with 'sk-ant-')."
                )
                    .font(.body)
            }

            infoCard(color: .blue) {
                Label("Step 3: Add to App", systemImage: "3.circle.fill")
                    .font(.headline)
                Text("Paste your API key in the settings above and \(PlatformVerb.tapLowercased) 'Save API Key'.")
                    .font(.body)
            }
        }
    }

    private var costSection: some View {
        infoCard(color: .green, spacing: 12) {
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
    }

    private var privacySection: some View {
        infoCard(color: .purple) {
            Label("Privacy & Security", systemImage: "lock.shield")
                .font(.headline)
            Text(
                "Your API key is stored securely on your device."
                + " Student data is sent directly to Anthropic's secure servers"
                + " for analysis and is not stored by Anthropic or any third parties."
            )
                .font(.body)
        }
    }

    private func infoCard<Content: View>(
        color: Color,
        spacing: CGFloat = 8,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: spacing, content: content)
            .padding()
            .background(color.opacity(UIConstants.OpacityConstants.light))
            .cornerRadius(12)
    }
}

// MARK: - Preview

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct APIKeySettingsViewPreview: View {
    var body: some View {
        NavigationStack {
            APIKeySettingsView()
        }
    }
}

#Preview {
    APIKeySettingsViewPreview()
}
