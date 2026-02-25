//
//  MCPClient.swift
//  Maria's Notebook
//
//  MCP (Model Context Protocol) client for external AI tool integration
//

import Foundation

/// Protocol defining the interface for MCP tool interactions
protocol MCPClientProtocol {
    /// Generates text using MCP's language model tools
    func generateText(prompt: String, temperature: Double) async throws -> String
    
    /// Generates text with system message and configurable max tokens
    func generateText(prompt: String, systemMessage: String?, temperature: Double, maxTokens: Int?) async throws -> String
    
    /// Generates structured JSON response using MCP's language model tools
    func generateStructuredJSON(prompt: String, temperature: Double) async throws -> String
    
    /// Generates structured JSON with system message and configurable max tokens
    func generateStructuredJSON(prompt: String, systemMessage: String?, temperature: Double, maxTokens: Int?) async throws -> String
    
    /// Generates text with full configuration including model and timeout
    func generateText(prompt: String, systemMessage: String?, temperature: Double, maxTokens: Int?, model: String?, timeout: TimeInterval?) async throws -> String
    
    /// Generates structured JSON with full configuration including model and timeout
    func generateStructuredJSON(prompt: String, systemMessage: String?, temperature: Double, maxTokens: Int?, model: String?, timeout: TimeInterval?) async throws -> String
    
    /// Analyzes text and extracts patterns
    func analyzePatterns(text: String, context: String) async throws -> [String]
    
    /// Searches external knowledge bases (e.g., educational standards, curriculum frameworks)
    func searchKnowledgeBase(query: String, domain: String) async throws -> [KnowledgeBaseResult]
}

// MARK: - Default Implementations

extension MCPClientProtocol {
    func generateText(prompt: String, systemMessage: String? = nil, temperature: Double, maxTokens: Int? = nil) async throws -> String {
        try await generateText(prompt: prompt, temperature: temperature)
    }
    
    func generateStructuredJSON(prompt: String, systemMessage: String? = nil, temperature: Double, maxTokens: Int? = nil) async throws -> String {
        try await generateStructuredJSON(prompt: prompt, temperature: temperature)
    }
    
    func generateText(prompt: String, systemMessage: String? = nil, temperature: Double, maxTokens: Int? = nil, model: String? = nil, timeout: TimeInterval? = nil) async throws -> String {
        try await generateText(prompt: prompt, systemMessage: systemMessage, temperature: temperature, maxTokens: maxTokens)
    }
    
    func generateStructuredJSON(prompt: String, systemMessage: String? = nil, temperature: Double, maxTokens: Int? = nil, model: String? = nil, timeout: TimeInterval? = nil) async throws -> String {
        try await generateStructuredJSON(prompt: prompt, systemMessage: systemMessage, temperature: temperature, maxTokens: maxTokens)
    }
}

/// Represents a result from an external knowledge base query
struct KnowledgeBaseResult: Codable {
    let title: String
    let summary: String
    let relevanceScore: Double
    let source: String
}

// MARK: - Production MCP Client

/// Production implementation that connects to actual MCP servers
final class MCPClient: MCPClientProtocol {
    
    private let serverURL: URL
    private let session: URLSession
    
    init(serverURL: URL, session: URLSession = .shared) {
        self.serverURL = serverURL
        self.session = session
    }
    
    func generateText(prompt: String, temperature: Double) async throws -> String {
        let request = MCPRequest(
            method: "generate_text",
            params: [
                "prompt": prompt,
                "temperature": temperature
            ]
        )
        
        let response: MCPResponse<String> = try await sendRequest(request)
        return response.result
    }
    
    func generateStructuredJSON(prompt: String, temperature: Double) async throws -> String {
        let request = MCPRequest(
            method: "generate_structured",
            params: [
                "prompt": prompt,
                "temperature": temperature,
                "format": "json"
            ]
        )
        
        let response: MCPResponse<String> = try await sendRequest(request)
        return response.result
    }
    
    func analyzePatterns(text: String, context: String) async throws -> [String] {
        let request = MCPRequest(
            method: "analyze_patterns",
            params: [
                "text": text,
                "context": context
            ]
        )
        
        let response: MCPResponse<[String]> = try await sendRequest(request)
        return response.result
    }
    
    func searchKnowledgeBase(query: String, domain: String) async throws -> [KnowledgeBaseResult] {
        let request = MCPRequest(
            method: "search_knowledge_base",
            params: [
                "query": query,
                "domain": domain
            ]
        )
        
        let response: MCPResponse<[KnowledgeBaseResult]> = try await sendRequest(request)
        return response.result
    }
    
    // MARK: - Private
    
    private func sendRequest<T: Decodable>(_ request: MCPRequest) async throws -> MCPResponse<T> {
        var urlRequest = URLRequest(url: serverURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        
        let (data, response) = try await session.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw MCPError.serverError(statusCode: httpResponse.statusCode)
        }
        
        do {
            return try JSONDecoder().decode(MCPResponse<T>.self, from: data)
        } catch {
            throw MCPError.decodingError(error)
        }
    }
}

// MARK: - Mock MCP Client (for Development & Testing)

/// Mock implementation that uses Apple's FoundationModels framework as a fallback
/// In a real implementation, this would connect to actual MCP servers
final class MockMCPClient: MCPClientProtocol {
    
    func generateText(prompt: String, temperature: Double) async throws -> String {
        // Simulate network delay
        try await Task.sleep(for: .seconds(0.5))
        
        // In production, this would call FoundationModels or return mock data
        return """
        This is a mock response for development purposes.
        In production, this would connect to an actual MCP server or use Apple's FoundationModels framework.
        
        Prompt received: \(prompt.prefix(100))...
        Temperature: \(temperature)
        """
    }
    
    func generateStructuredJSON(prompt: String, temperature: Double) async throws -> String {
        // Simulate network delay
        try await Task.sleep(for: .seconds(0.5))
        
        // Return mock structured analysis
        let mockResponse = MCPAnalysisResponse(
            overallProgress: "The student shows steady progress across academic and social domains. Notable growth in independence and peer collaboration.",
            keyStrengths: [
                "Strong focus and concentration during practice",
                "Demonstrates helping behavior with peers",
                "Growing independence in work selection"
            ],
            areasForGrowth: [
                "Continue building confidence in new materials",
                "Develop strategies for handling frustration"
            ],
            developmentalMilestones: [
                "Achieved consistent 3-period lesson retention",
                "Demonstrates age-appropriate fine motor control"
            ],
            observedPatterns: [
                "Works best in morning sessions",
                "Prefers hands-on materials over abstract concepts",
                "Shows increased engagement with peer practice"
            ],
            behavioralTrends: [
                "Increasing independence over the analysis period",
                "More frequent peer collaboration"
            ],
            socialEmotionalInsights: [
                "Developing conflict resolution skills",
                "Shows empathy when peers struggle"
            ],
            recommendedNextLessons: [
                "Introduction to more complex math materials",
                "Extended practical life challenges"
            ],
            suggestedPracticeFocus: [
                "Sustained focus on multi-step tasks",
                "Building stamina for longer work cycles"
            ],
            interventionSuggestions: [
                "Provide additional scaffolding for new abstract concepts",
                "Create more opportunities for peer teaching"
            ]
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(mockResponse)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
    
    func analyzePatterns(text: String, context: String) async throws -> [String] {
        // Simulate network delay
        try await Task.sleep(for: .seconds(0.3))
        
        return [
            "Pattern 1: Repeated engagement with similar materials",
            "Pattern 2: Increased time spent on tasks over period",
            "Pattern 3: Growing comfort with peer interaction"
        ]
    }
    
    func searchKnowledgeBase(query: String, domain: String) async throws -> [KnowledgeBaseResult] {
        // Simulate network delay
        try await Task.sleep(for: .seconds(0.4))
        
        return [
            KnowledgeBaseResult(
                title: "Montessori Developmental Milestones: Ages 3-6",
                summary: "Comprehensive guide to expected developmental milestones in the primary Montessori classroom",
                relevanceScore: 0.92,
                source: "AMI Standards Database"
            ),
            KnowledgeBaseResult(
                title: "Social-Emotional Development in Early Childhood",
                summary: "Research-based framework for understanding social-emotional growth in young learners",
                relevanceScore: 0.87,
                source: "Educational Psychology Journal"
            )
        ]
    }
}

// MARK: - MCP Protocol Types

struct MCPRequest: Encodable {
    let method: String
    let params: [String: Any]
    
    enum CodingKeys: String, CodingKey {
        case method
        case params
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(method, forKey: .method)
        
        // Convert params dictionary to JSON
        let paramsData = try JSONSerialization.data(withJSONObject: params)
        let paramsJSON = try JSONSerialization.jsonObject(with: paramsData)
        try container.encode(paramsJSON as? [String: String] ?? [:], forKey: .params)
    }
}

struct MCPResponse<T: Decodable>: Decodable {
    let result: T
    let metadata: MCPMetadata?
}

struct MCPMetadata: Decodable {
    let processingTime: Double?
    let model: String?
    let tokensUsed: Int?
}

enum MCPError: Error, LocalizedError {
    case invalidResponse
    case serverError(statusCode: Int)
    case decodingError(Error)
    case networkError(Error)
    case configurationError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from MCP server"
        case .serverError(let statusCode):
            return "MCP server error: HTTP \(statusCode)"
        case .decodingError(let error):
            return "Failed to decode MCP response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        }
    }
}
