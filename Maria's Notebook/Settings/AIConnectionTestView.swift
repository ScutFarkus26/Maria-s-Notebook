import SwiftUI

// MARK: - AI Connection Test View

/// Sends a test prompt to the configured AI model to verify the setup works.
struct AIConnectionTestView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var testSuccess = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Send a test prompt to verify your AI configuration works correctly.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                Task { await runTest() }
            } label: {
                HStack(spacing: 6) {
                    if isTesting {
                        ProgressView()
                            .scaleEffect(SettingsStyle.toggleScale)
                    }
                    Text(isTesting ? "Testing..." : "Test Connection")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isTesting)

            if let result = testResult {
                HStack(alignment: .top, spacing: 8) {
                    Image(
                        systemName: testSuccess
                            ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .foregroundStyle(testSuccess ? AppColors.success : AppColors.destructive)
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(testSuccess ? AppColors.success : AppColors.destructive)
                        .lineLimit(4)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            (testSuccess ? AppColors.success : AppColors.destructive).opacity(UIConstants.OpacityConstants.light)
                        )
                )
            }
        }
    }

    private func runTest() async {
        isTesting = true
        testResult = nil
        do {
            let router = dependencies.aiRouter
            router.activeFeatureArea = .chat
            let response = try await router.generateText(
                prompt: "Reply with exactly: 'Connection successful'",
                systemMessage: "You are a test assistant. Reply concisely with the requested text.",
                temperature: 0.0,
                maxTokens: 20,
                model: nil,
                timeout: 15
            )
            testSuccess = true
            testResult = "Success: \(String(response.prefix(100)))"
        } catch {
            testSuccess = false
            testResult = error.localizedDescription
        }
        isTesting = false
    }
}
