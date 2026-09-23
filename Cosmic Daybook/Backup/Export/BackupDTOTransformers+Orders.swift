import Foundation
import CoreData

// MARK: - Format v27 Transformers

extension BackupDTOTransformers {

    // MARK: - CDOrderItem

    static func toDTO(_ item: CDOrderItem) -> OrderItemDTO {
        OrderItemDTO(
            id: item.id ?? UUID(),
            urlString: item.urlString,
            title: item.title,
            quantity: Int(item.quantity),
            notes: item.notes,
            requestID: item.requestID,
            requestedFrom: item.requestedFrom,
            requestedAt: item.requestedAt,
            confirmedAt: item.confirmedAt,
            receivedAt: item.receivedAt,
            createdAt: item.createdAt ?? Date(),
            modifiedAt: item.modifiedAt ?? Date()
        )
    }

    static func toDTOs(_ items: [CDOrderItem]) -> [OrderItemDTO] {
        items.map { toDTO($0) }
    }
}

// MARK: - Collection

extension BackupService {
    /// Collects the format v27 entity type: Orders. Lives here rather than in
    /// BackupService+DataCollection, which is at SwiftLint's file-length limit.
    func collectOrderDTOs(into payload: inout BackupPayload, using viewContext: NSManagedObjectContext) {
        payload.orderItems = fetchAndTransformInBatches(
            CDOrderItem.self, using: viewContext) { BackupDTOTransformers.toDTOs($0) }
    }
}
