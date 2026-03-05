import Foundation
import SwiftData

// MARK: - Document/Supply/Procedure Imports

extension BackupEntityImporter {

    // MARK: - Documents

    static func importDocuments(
        _ dtos: [DocumentDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<Document>,
        studentCheck: EntityExistsCheck<Student>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let d = Document(
                id: dto.id,
                title: dto.title,
                category: dto.category,
                uploadDate: dto.uploadDate
            )
            if let studentID = dto.studentID {
                do {
                    if let student = try studentCheck(studentID) {
                        d.student = student
                    }
                } catch {
                    print("\u{26a0}\u{fe0f} [Backup:\(#function)] Failed to check student for document: \(error)")
                }
            }
            modelContext.insert(d)
        }
    }

    // MARK: - Supplies

    static func importSupplies(
        _ dtos: [SupplyDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<Supply>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: modelContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let s = Supply(
                id: dto.id,
                name: dto.name,
                category: SupplyCategory(rawValue: dto.categoryRaw) ?? .other,
                location: dto.location,
                currentQuantity: dto.currentQuantity,
                minimumThreshold: dto.minimumThreshold,
                reorderAmount: dto.reorderAmount,
                unit: dto.unit,
                notes: dto.notes,
                createdAt: dto.createdAt,
                modifiedAt: dto.modifiedAt
            )
            return s
        })
    }

    // MARK: - Supply Transactions

    static func importSupplyTransactions(
        _ dtos: [SupplyTransactionDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<SupplyTransaction>,
        supplyCheck: EntityExistsCheck<Supply>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let t = SupplyTransaction(
                id: dto.id,
                supplyID: dto.supplyID,
                date: dto.date,
                quantityChange: dto.quantityChange,
                reason: dto.reason
            )
            if let supplyUUID = UUID(uuidString: dto.supplyID) {
                do {
                    if let supply = try supplyCheck(supplyUUID) {
                        t.supply = supply
                    }
                } catch {
                    print("\u{26a0}\u{fe0f} [Backup:\(#function)] Failed to check supply for transaction: \(error)")
                }
            }
            modelContext.insert(t)
        }
    }

    // MARK: - Procedures

    static func importProcedures(
        _ dtos: [ProcedureDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<Procedure>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: modelContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let p = Procedure(
                id: dto.id,
                title: dto.title,
                summary: dto.summary,
                content: dto.content,
                category: ProcedureCategory(rawValue: dto.categoryRaw) ?? .other,
                icon: dto.icon,
                relatedProcedureIDs: dto.relatedProcedureIDs,
                createdAt: dto.createdAt,
                modifiedAt: dto.modifiedAt
            )
            return p
        })
    }
}
