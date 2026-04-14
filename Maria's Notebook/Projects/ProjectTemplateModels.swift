import Foundation
import OSLog

// MARK: - JSON Helpers
struct JSONStringList {
    private static let logger = Logger.projects
    nonisolated static func encode(_ arr: [String]) -> String {
        guard !arr.isEmpty else { return "" }
        do {
            let data = try JSONEncoder().encode(arr)
            if let s = String(data: data, encoding: .utf8) {
                return s
            }
        } catch {
            Self.logger.warning("Failed to encode string array: \(error)")
        }
        return ""
    }
    nonisolated static func decode(_ s: String) -> [String] {
        let trimmed = s.trimmed()
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return [] }
        do {
            let arr = try JSONDecoder().decode([String].self, from: data)
            return arr
        } catch {
            Self.logger.warning("Failed to decode string array: \(error)")
            return []
        }
    }
}

// TemplateOfferedWork and TemplateOfferedWorksJSON removed — CDProjectTemplateWeek deprecated.
