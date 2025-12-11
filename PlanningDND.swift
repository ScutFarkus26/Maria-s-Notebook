import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let planningDragItem = UTType(exportedAs: "com.yourorg.planning.drag-item")
}

struct PlanningDragItem: Codable, Transferable, Equatable {
    enum Kind: String, Codable { case work, checkIn }
    let kind: Kind
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .planningDragItem)
    }

    static func work(_ id: UUID) -> PlanningDragItem { .init(kind: .work, id: id) }
    static func checkIn(_ id: UUID) -> PlanningDragItem { .init(kind: .checkIn, id: id) }
}
