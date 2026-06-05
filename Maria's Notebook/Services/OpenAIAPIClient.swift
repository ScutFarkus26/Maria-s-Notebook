//
//  OpenAIAPIClient.swift
//  Maria's Notebook
//
//  Direct OpenAI client used for image generation (gpt-image-1).
//  Mirrors the keychain-backed key management pattern in `AnthropicAPIClient`.
//

import Foundation
import OSLog

/// Minimal OpenAI client. Today this only exposes image generation; can grow if we
/// later need OpenAI for other modalities.
final class OpenAIAPIClient {
    static let logger = Logger.ai

    let apiKey: String
    let session: URLSession
    private let imagesURL: URL

    init(apiKey: String? = nil, session: URLSession = .shared) {
        self.apiKey = apiKey ?? Self.loadAPIKey()
        self.session = session
        guard let url = URL(string: "https://api.openai.com/v1/images/generations") else {
            preconditionFailure("Invalid hardcoded OpenAI image URL. This is a programming error.")
        }
        self.imagesURL = url
    }

    // MARK: - Image Generation

    enum ImageSize: String {
        case square = "1024x1024"
        case portrait = "1024x1536"
        case landscape = "1536x1024"
    }

    enum ImageQuality: String {
        case low
        case medium
        case high
        case auto
    }

    /// Generates a single image with `gpt-image-1`. Returns the raw bytes (PNG by default).
    /// - Parameters:
    ///   - prompt: Description of the image to render.
    ///   - size: Requested aspect ratio. Defaults to `.portrait` for storybook covers.
    ///   - quality: Cost/quality knob. Defaults to `.low` for thumbnails (~$0.01 each).
    func generateImage(
        prompt: String,
        size: ImageSize = .portrait,
        quality: ImageQuality = .low
    ) async throws -> Data {
        try validateAPIKey()

        let body: [String: Any] = [
            "model": "gpt-image-1",
            "prompt": prompt,
            "n": 1,
            "size": size.rawValue,
            "quality": quality.rawValue
        ]

        var request = URLRequest(url: imagesURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        Self.logger.debug(
            "Requesting OpenAI image, prompt length=\(prompt.count, privacy: .public), size=\(size.rawValue, privacy: .public)"
        )

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw OpenAIAPIError.invalidResponse
            }
            guard http.statusCode == 200 else {
                throw buildHTTPError(statusCode: http.statusCode, data: data)
            }
            return try parseImageResponse(data)
        } catch let error as OpenAIAPIError {
            throw error
        } catch {
            throw mapNetworkError(error)
        }
    }

    // MARK: - Private

    private func validateAPIKey() throws {
        guard !apiKey.isEmpty else {
            throw OpenAIAPIError.noAPIKey
        }
    }

    private func parseImageResponse(_ data: Data) throws -> Data {
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let array = body["data"] as? [[String: Any]],
              let first = array.first,
              let b64 = first["b64_json"] as? String,
              let bytes = Data(base64Encoded: b64) else {
            throw OpenAIAPIError.invalidResponseFormat
        }
        return bytes
    }

    private func buildHTTPError(statusCode: Int, data: Data) -> OpenAIAPIError {
        let raw = String(data: data, encoding: .utf8) ?? ""
        Self.logger.debug("OpenAI HTTP \(statusCode, privacy: .public): \(raw, privacy: .private)")

        let serverMessage: String
        if let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = body["error"] as? [String: Any],
           let message = error["message"] as? String {
            serverMessage = message
        } else if !raw.isEmpty {
            serverMessage = raw
        } else {
            serverMessage = "Unknown error"
        }

        let helpful: String
        switch statusCode {
        case 401:
            helpful = "Invalid OpenAI API key. Check your key in Settings. \(serverMessage)"
        case 429:
            helpful = "OpenAI rate limit exceeded. Try again in a moment. \(serverMessage)"
        case 400:
            helpful = "OpenAI rejected the request: \(serverMessage)"
        case 500, 502, 503:
            helpful = "OpenAI is temporarily unavailable. Try again. \(serverMessage)"
        default:
            helpful = serverMessage
        }
        return .apiError(statusCode: statusCode, message: helpful)
    }

    private func mapNetworkError(_ error: Error) -> OpenAIAPIError {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return .apiError(statusCode: 0, message: "No internet connection. Please check your network.")
            case .cannotFindHost, .cannotConnectToHost:
                return .apiError(
                    statusCode: 0,
                    message: "Cannot reach api.openai.com. Check your connection or firewall."
                )
            case .timedOut:
                return .apiError(statusCode: 0, message: "Request timed out. Try again.")
            default:
                return .apiError(statusCode: 0, message: "Network error: \(urlError.localizedDescription)")
            }
        }
        return .apiError(statusCode: 0, message: "Network error: \(error.localizedDescription)")
    }
}

// MARK: - API Key Management

extension OpenAIAPIClient {

    private static let keychain = KeychainStore(
        service: "com.danielsdeberry.MariasNoteBook",
        account: "openAIAPIKey"
    )

    static func loadAPIKey() -> String {
        if let data = try? keychain.get(), let key = String(data: data, encoding: .utf8), !key.isEmpty {
            return key
        }
        // Fall back to UserDefaults and auto-migrate.
        if let key = UserDefaults.standard.string(forKey: "openAIAPIKey"), !key.isEmpty {
            if let data = key.data(using: .utf8) {
                try? keychain.set(data)
                UserDefaults.standard.removeObject(forKey: "openAIAPIKey")
                logger.info("Migrated OpenAI key from UserDefaults to Keychain")
            }
            return key
        }
        return ""
    }

    static func saveAPIKey(_ key: String) {
        guard let data = key.data(using: .utf8) else { return }
        do {
            try keychain.set(data)
        } catch {
            logger.error("Failed to save OpenAI API key: \(error.localizedDescription)")
        }
    }

    /// Whether a non-empty, plausibly-shaped OpenAI key is configured.
    static func hasAPIKey() -> Bool {
        let key = loadAPIKey()
        return !key.isEmpty && key.hasPrefix("sk-")
    }

    static func clearAPIKey() {
        try? keychain.delete()
        UserDefaults.standard.removeObject(forKey: "openAIAPIKey")
    }
}

// MARK: - Errors

enum OpenAIAPIError: Error, LocalizedError {
    case noAPIKey
    case invalidResponse
    case invalidResponseFormat
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "OpenAI API key not configured. Add your key in Settings to generate covers."
        case .invalidResponse:
            return "Invalid response from OpenAI."
        case .invalidResponseFormat:
            return "Unexpected response format from OpenAI."
        case .apiError(let statusCode, let message):
            return "OpenAI error (\(statusCode)): \(message)"
        }
    }
}
