import Foundation

// Orders (format v27+).

nonisolated public struct OrderItemDTO: Codable, Sendable {
    public var id: UUID
    public var urlString: String
    public var title: String
    public var quantity: Int
    public var notes: String
    public var requestID: String?
    public var requestedFrom: String
    public var requestedAt: Date?
    public var confirmedAt: Date?
    public var receivedAt: Date?
    public var createdAt: Date
    public var modifiedAt: Date
}
