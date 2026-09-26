//
//  AppLaunchMode.swift
//  Cosmic Daybook
//
//  How this process was started. When a Claude session starts and the Mac
//  app isn't running, the MCP bridge (Scripts/mcp/cosmic-daybook-mcp)
//  launches it with `-CosmicDaybookMCPAutolaunch YES`: the app then comes up
//  as a server only — no main window — and quits once Claude has been gone
//  for a while (MCPIdleQuitPolicy). Every other launch is a normal one.
//

import Foundation

nonisolated enum AppLaunchMode: Equatable, Sendable {
    /// Danny opened the app, or Xcode ran it: everything as it always was.
    case normal
    /// The MCP bridge started the app for a Claude session.
    case mcpOnly

    /// The launch argument the bridge passes, followed by `YES`.
    static let mcpAutolaunchArgument = "-CosmicDaybookMCPAutolaunch"

    /// This process's mode, read once from its launch arguments. Read from
    /// argv rather than `UserDefaults`: a `-Key Value` argument also lands in
    /// the volatile argument domain, but a value somebody had written to the
    /// app's persistent defaults would then make every launch MCP-only.
    static let current = resolve(arguments: ProcessInfo.processInfo.arguments)

    /// `-CosmicDaybookMCPAutolaunch` followed by a true value (YES, true or 1,
    /// in any case) is an MCP-only launch; anything else is a normal one.
    static func resolve(arguments: [String]) -> AppLaunchMode {
        guard let flag = arguments.firstIndex(of: mcpAutolaunchArgument),
              arguments.indices.contains(flag + 1) else { return .normal }
        switch arguments[flag + 1].lowercased() {
        case "yes", "true", "1":
            return .mcpOnly
        default:
            return .normal
        }
    }
}
