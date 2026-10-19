// TideAddress.swift
// Tide's connection address, as Danny pastes it into Settings.

import Foundation

/// Tide's connection address, copied from Tide's Settings › Claude:
/// `http://localhost:4877/<40 hex characters>/mcp`. Tide answers it only on
/// this Mac and only while Tide is open; the 40 characters are its token, and
/// a request without the right one gets HTTP 401 (`MCPHTTPTransport`).
///
/// Always kept with the host spelled `localhost`. App Transport Security
/// allows plain HTTP to an unqualified host name such as `localhost` by
/// default, but since macOS 14 no longer to an IP address
/// (`NSAllowsLocalNetworking`, checked 2026-10-18), so an address pasted as
/// `127.0.0.1` or `[::1]` is rewritten rather than given an exception. Tide's
/// server accepts `localhost` in the Host header (the SDK's localhost origin
/// rule).
nonisolated struct TideAddress: Equatable, Sendable {
    let url: URL

    /// Why a pasted address can't be used, in words for the person.
    enum Problem: Error, Equatable, LocalizedError {
        case empty
        case notTideAddress
        case notOnThisMac
        case missingToken

        var errorDescription: String? {
            switch self {
            case .empty:
                "Paste the address from Tide's Settings › Claude."
            case .notTideAddress:
                "That isn't Tide's address. Copy it from Tide's Settings › Claude and paste it here."
            case .notOnThisMac:
                "That address isn't for Tide on this Mac. Copy the one Tide's Settings › Claude shows."
            case .missingToken:
                "Part of the address is missing. Copy the whole address from Tide's Settings › Claude."
            }
        }
    }

    static let defaultPort = 4877
    private static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "[::1]"]

    /// The address in `text`, cleaned up, or why it can't be used.
    static func parse(_ text: String) -> Result<TideAddress, Problem> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        let withScheme = trimmed.contains("://") ? trimmed : "http://" + trimmed
        guard let parts = URLComponents(string: withScheme),
              let scheme = parts.scheme?.lowercased(), scheme == "http",
              let host = parts.host?.lowercased() else { return .failure(.notTideAddress) }
        guard loopbackHosts.contains(host) else { return .failure(.notOnThisMac) }
        let segments = parts.path.split(separator: "/").map(String.init)
        guard let token = segments.first, token.count == 40, token.allSatisfy(\.isHexDigit) else {
            return .failure(.missingToken)
        }
        var clean = URLComponents()
        clean.scheme = "http"
        clean.host = "localhost"
        clean.port = parts.port ?? defaultPort
        clean.path = "/\(token)/mcp"
        guard let url = clean.url else { return .failure(.notTideAddress) }
        return .success(TideAddress(url: url))
    }
}
