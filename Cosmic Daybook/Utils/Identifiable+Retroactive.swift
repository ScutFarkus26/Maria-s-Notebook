import Foundation

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
