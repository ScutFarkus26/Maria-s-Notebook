import Foundation

// MARK: - Core DTOs

nonisolated public struct ItemDTO: Codable, Sendable {
    public var id: UUID
    public var timestamp: Date
}

// MARK: - Template DTOs
