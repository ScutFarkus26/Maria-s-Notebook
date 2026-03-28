import Foundation
import SwiftUI

// MARK: - Ollama API Types
// Extracted from OllamaClient for type_body_length compliance

struct OllamaModel: Codable, Identifiable {
    let name: String
    let size: Int64
    let digest: String
    let modifiedAt: String

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, size, digest
        case modifiedAt = "modified_at"
    }
}

struct OllamaTagsResponse: Codable {
    let models: [OllamaModel]
}

struct OllamaGenerateResponse: Codable {
    let response: String
}

struct OllamaChatResponse: Codable {
    let message: OllamaChatMessage
}

struct OllamaChatMessage: Codable {
    let role: String
    let content: String
}

struct OllamaChatStreamChunk: Codable {
    let message: OllamaChatMessage
    let done: Bool
}

// MARK: - Pull API Types

/// Progress update during an Ollama model pull operation.
struct OllamaPullProgress: Sendable {
    let status: String
    let completed: Int64?
    let total: Int64?

    /// Fraction completed (0.0 to 1.0), or nil if not in a download phase.
    var fractionCompleted: Double? {
        guard let total, total > 0, let completed else { return nil }
        return Double(completed) / Double(total)
    }
}

struct OllamaPullChunk: Codable {
    let status: String
    let digest: String?
    let total: Int64?
    let completed: Int64?
}

// MARK: - Model Catalog

/// Describes a popular Ollama model available for installation.
struct OllamaModelCatalog: Identifiable {
    let id: String
    let name: String
    let parameterCount: String
    let sizeGB: Double
    let description: String

    /// Curated list of recommended models for classroom use.
    static let recommended: [OllamaModelCatalog] = [
        OllamaModelCatalog(
            id: "llama3.2",
            name: "Llama 3.2",
            parameterCount: "3B",
            sizeGB: 2.0,
            description: "Meta's compact model. Good balance of speed and quality."
        ),
        OllamaModelCatalog(
            id: "gemma2:9b",
            name: "Gemma 2 9B",
            parameterCount: "9B",
            sizeGB: 5.5,
            description: "Google's model. Best quality, needs 16GB+ RAM."
        )
    ]
}

// MARK: - Errors

enum OllamaError: Error, LocalizedError {
    case serverUnreachable
    case serverError(statusCode: Int, detail: String = "")
    case invalidResponse
    case invalidJSON(String)
    case timeout
    case networkError(String)
    case modelNotFound(String)
    case pullFailed(String)

    static func from(_ urlError: URLError) -> OllamaError {
        switch urlError.code {
        case .cannotConnectToHost, .cannotFindHost: return .serverUnreachable
        case .timedOut: return .timeout
        default: return .networkError(urlError.localizedDescription)
        }
    }

    var errorDescription: String? {
        switch self {
        case .serverUnreachable:
            return "Cannot connect to Ollama. Make sure Ollama is running (ollama serve)."
        case .serverError(let code, let detail):
            return "Ollama server error (\(code))\(detail.isEmpty ? "" : ": \(detail)")"
        case .invalidResponse:
            return "Invalid response from Ollama server."
        case .invalidJSON(let text):
            return "Ollama returned invalid JSON: \(text.prefix(100))..."
        case .timeout:
            return "Ollama request timed out. The model may be loading — try again."
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .modelNotFound(let name):
            return "Model '\(name)' not found. Run: ollama pull \(name)"
        case .pullFailed(let name):
            return "Failed to pull model '\(name)'. The download may have been interrupted."
        }
    }
}
