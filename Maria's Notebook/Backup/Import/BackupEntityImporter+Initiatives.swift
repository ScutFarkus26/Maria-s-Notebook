import Foundation
import CoreData

// MARK: - Initiative (format v15+)

extension BackupEntityImporter {

    static func importInitiatives(
        _ dtos: [InitiativeDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDInitiative>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
                let i = CDInitiative(context: viewContext)
                i.id = dto.id
                i.title = dto.title
                i.notes = dto.notes
                i.deadline = dto.deadline
                i.completedAt = dto.completedAt
                i.area = dto.area
                i.colorRaw = dto.colorRaw
                i.symbol = dto.symbol
                i.orderIndex = Int64(dto.orderIndex)
                i.createdAt = dto.createdAt
                i.modifiedAt = dto.modifiedAt
                i.notificationIDsArray = dto.notificationIDs
                if let leadTimes = dto.leadTimeDays {
                    i.leadTimeDaysArray = leadTimes
                }
                return i
            })
    }
}
