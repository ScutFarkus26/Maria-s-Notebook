import Foundation

/// Shared utilities for CSV header mapping and validation.
/// Consolidates header mapping logic used across CSV importers.
enum CSVHeaderMapping {
    /// Finds the index of a header matching any of the candidate strings.
    /// - Parameters:
    ///   - candidates: Array of candidate header names to match
    ///   - headers: Array of header strings (normalized to lowercase)
    /// - Returns: Index of matching header, or nil if not found
    static func findIndex(candidates: [String], in headers: [String]) -> Int? {
        for candidate in candidates {
            if let idx = headers.firstIndex(of: candidate.lowercased()) {
                return idx
            }
        }
        return nil
    }
    
    /// Builds a header mapping dictionary from normalized headers.
    /// - Parameters:
    ///   - headers: Array of header strings
    ///   - synonymMap: Dictionary mapping canonical keys to candidate arrays
    /// - Returns: Dictionary mapping canonical keys to header indices
    static func buildMapping(
        headers: [String],
        synonymMap: [String: [String]]
    ) -> [String: Int] {
        let normalized = headers.map { $0.normalizedForComparison() }
        var result: [String: Int] = [:]
        
        for (canonicalKey, candidates) in synonymMap {
            if let index = findIndex(candidates: candidates, in: normalized) {
                result[canonicalKey] = index
            }
        }
        
        return result
    }
    
}

/// Common CSV import errors
enum CSVImportError: Error, LocalizedError {
    case missingRequiredHeaders([String])
    case invalidHeaderFormat(String)
    
    var errorDescription: String? {
        switch self {
        case .missingRequiredHeaders(let headers):
            return "Missing required headers: \(headers.joined(separator: ", "))"
        case .invalidHeaderFormat(let message):
            return "Invalid header format: \(message)"
        }
    }
}
