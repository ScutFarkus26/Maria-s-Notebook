import Foundation
import CoreData

// MARK: - Order importers (format v27+)

extension BackupEntityImporter {

    // MARK: - CDOrderItem

    static func importOrderItems(
        _ dtos: [OrderItemDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDOrderItem>
    ) {
        for dto in dtos {
            let entity = existingEntity(id: dto.id, existing: existing) ?? CDOrderItem(context: viewContext)
            entity.id = dto.id
            entity.urlString = dto.urlString
            entity.title = dto.title
            entity.quantity = Int64(dto.quantity)
            entity.notes = dto.notes
            entity.requestID = dto.requestID
            entity.requestedFrom = dto.requestedFrom
            entity.requestedAt = dto.requestedAt
            entity.confirmedAt = dto.confirmedAt
            entity.receivedAt = dto.receivedAt
            entity.createdAt = dto.createdAt
            entity.modifiedAt = dto.modifiedAt
        }
    }
}
