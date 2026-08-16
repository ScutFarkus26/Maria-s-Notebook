//
//  ClaudeDesktopSettingsView.swift
//  Maria's Notebook
//
//  macOS-only Settings pane for the in-app MCP server that lets Claude
//  Desktop (and other MCP clients) read the notebook and record
//  observations. Off by default: exposing student data to an external
//  AI client is an explicit teacher choice.
//

#if os(macOS)
import SwiftUI

struct ClaudeDesktopSettingsView: View {
    @AppStorage(UserDefaultsKeys.aiMCPServerEnabled) private var mcpServerEnabled = false

    var body: some View {
        let service = MCPServerService.shared
        VStack(alignment: .leading, spacing: SettingsStyle.groupSpacing) {
            Toggle(isOn: $mcpServerEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Allow Claude Desktop Access")
                    Text(
                        "Lets Claude Desktop look up students, observations, lessons, and "
                        + "presentations, and record observations you dictate. Claude Desktop "
                        + "asks before each tool runs. Data you discuss there is sent to Anthropic."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if mcpServerEnabled {
                Divider()
                if service.isRunning {
                    Label("Listening for Claude Desktop", systemImage: "circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                } else if let error = service.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
                Text(
                    "Claude Desktop connects through the bridge script at Scripts/mcp/marias-notebook-mcp "
                    + "in the project repository; see Documentation/Architecture/MCP_SERVER.md for setup."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .onChange(of: mcpServerEnabled) { _, _ in
            MCPServerService.shared.applySettings()
            SettingsCategory.markModified(.aiFeatures)
        }
    }
}
#endif
