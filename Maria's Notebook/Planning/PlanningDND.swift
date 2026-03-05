import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    // Use importedAs to avoid requiring an Info.plist exported type declaration during development.
    static let planningDragItem = UTType(importedAs: "com.yourorg.planning.drag-item")
}

struct PlanningDragItem: Codable, Transferable, Equatable {
    enum Kind: String, Codable { case work, checkIn }
    let kind: Kind
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.stringPayload)
    }
    
    private var stringPayload: String {
        switch kind {
        case .work:
            return "WORK:\(id.uuidString)"
        case .checkIn:
            return "CHECKIN:\(id.uuidString)"
        }
    }

    static func work(_ id: UUID) -> PlanningDragItem { .init(kind: .work, id: id) }
    static func checkIn(_ id: UUID) -> PlanningDragItem { .init(kind: .checkIn, id: id) }
}
