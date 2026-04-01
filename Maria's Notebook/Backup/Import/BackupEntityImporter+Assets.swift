import Foundation
import CoreData
import OSLog

// MARK: - CDDocument/CDSupply/CDProcedure Imports

extension BackupEntityImporter {

    // MARK: - Documents

    static func importDocuments(
        _ dtos: [DocumentDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDDocument>,
        studentCheck: EntityExistsCheck<CDStudent>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let d = CDDocument(context: viewContext)
            d.id = dto.id
            d.title = dto.title
            d.category = dto.category
            d.uploadDate = dto.uploadDate
            if let studentID = dto.studentID {
                do {
                    if let student = try studentCheck(studentID) {
                        d.student = student
                    }
                } catch {
                    let desc = error.localizedDescription
                    Logger.backup.warning("Failed to check student for document: \(desc, privacy: .public)")
                }
            }
            viewContext.insert(d)
        }
    }

    // MARK: - Supplies

    static func importSupplies(
        _ dtos: [SupplyDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDSupply>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let s = CDSupply(context: viewContext)
            s.id = dto.id
            s.name = dto.name
            s.categoryRaw = (SupplyCategory(rawValue: dto.categoryRaw) ?? .other).rawValue
            s.location = dto.location
            s.currentQuantity = Int64(dto.currentQuantity)
            s.minimumThreshold = Int64(dto.minimumThreshold)
            s.reorderAmount = Int64(dto.reorderAmount)
            s.unit = dto.unit
            s.notes = dto.notes
            s.createdAt = dto.createdAt
            s.modifiedAt = dto.modifiedAt
            return s
        })
    }

    // MARK: - CDSupply Transactions

    static func importSupplyTransactions(
        _ dtos: [SupplyTransactionDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDSupplyTransaction>,
        supplyCheck: EntityExistsCheck<CDSupply>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let t = CDSupplyTransaction(context: viewContext)
            t.id = dto.id
            t.supplyID = dto.supplyID
            t.date = dto.date
            t.quantityChange = Int64(dto.quantityChange)
            t.reason = dto.reason
            if let supplyUUID = UUID(uuidString: dto.supplyID) {
                do {
                    if let supply = try supplyCheck(supplyUUID) {
                        t.supply = supply
                    }
                } catch {
                    let desc = error.localizedDescription
                    Logger.backup.warning("Failed to check supply for transaction: \(desc, privacy: .public)")
                }
            }
            viewContext.insert(t)
        }
    }

    // MARK: - Procedures

    static func importProcedures(
        _ dtos: [ProcedureDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDProcedure>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let p = CDProcedure(context: viewContext)
            p.id = dto.id
            p.title = dto.title
            p.summary = dto.summary
            p.content = dto.content
            p.categoryRaw = (ProcedureCategory(rawValue: dto.categoryRaw) ?? .other).rawValue
            p.icon = dto.icon
            p.relatedProcedureIDs = dto.relatedProcedureIDs
            p.createdAt = dto.createdAt
            p.modifiedAt = dto.modifiedAt
            return p
        })
    }
}
