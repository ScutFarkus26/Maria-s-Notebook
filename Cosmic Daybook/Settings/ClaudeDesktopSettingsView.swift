//
//  ClaudeDesktopSettingsView.swift
//  Cosmic Daybook
//
//  macOS-only Settings pane for the in-app MCP server that lets Claude
//  Desktop (and other MCP clients) read and update the whole notebook.
//  Off by default: exposing student data to an external AI client is an
//  explicit teacher choice.
//

#if os(macOS)
import SwiftUI

struct ClaudeDesktopSettingsView: View {
    @AppStorage(UserDefaultsKeys.aiMCPServerEnabled) private var mcpServerEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsStyle.groupSpacing) {
            Toggle(isOn: $mcpServerEnabled) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                    Text("Allow Claude Desktop access")
                    Text(
                        "Claude Desktop can read and update your whole notebook: students, lessons, "
                        + "presentations, observations, work, attendance, meetings and more. It asks "
                        + "before each change. What you discuss there is sent to Anthropic."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if mcpServerEnabled {
                Divider()
                status
                Text(
                    "Claude Desktop needs a one-time connection set up on this Mac. After that, "
                    + "it opens your notebook on its own whenever you ask it something."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .onChange(of: mcpServerEnabled) { _, _ in
            MCPServerService.shared.applySettings()
        }
    }

    /// Always says something while the toggle is on: listening, why it
    /// stopped, or that it is still starting.
    @ViewBuilder
    private var status: some View {
        let service = MCPServerService.shared
        if service.isRunning {
            Label(
                service.connectedClientCount > 0 ? "Connected to Claude Desktop" : "Ready for Claude Desktop",
                systemImage: "circle.fill"
            )
            .foregroundStyle(AppColors.success)
            .font(.caption)
        } else if let error = service.lastError {
            Label("Not running: \(error)", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(AppColors.warning)
                .font(.caption)
        } else {
            HStack(spacing: AppTheme.Spacing.verySmall) {
                ProgressView()
                    .controlSize(.small)
                Text("Starting…")
            }
            .foregroundStyle(.secondary)
            .font(.caption)
        }
    }
}
#endif
