//
//  OpenAIAPIKeySettingsView.swift
//  Cosmic Daybook
//
//  Settings view for configuring an OpenAI API key (used for story cover generation
//  via gpt-image-1). Mirrors `APIKeySettingsView` for the Anthropic key.
//

import SwiftUI

/// OpenAI key screen. The screen itself is `APIKeyProviderSettingsView`;
/// this wrapper keeps the name its callers already use.
struct OpenAIAPIKeySettingsView: View {
    var body: some View {
        APIKeyProviderSettingsView(provider: .openAI)
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
