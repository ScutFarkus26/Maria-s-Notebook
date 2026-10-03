import Foundation
import CoreData
import OSLog

// MARK: - CDDocument/CDSupply/CDProcedure Imports

extension BackupEntityImporter {

    // MARK: - Documents

    static func importDocuments(
        _ dtos: [DocumentDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDDocument>
    ) rethrows {
        for dto in dtos {
            let d = existingEntity(id: dto.id, existing: existing) ?? CDDocument(context: viewContext)
            d.id = dto.id
            d.title = dto.title
            d.category = dto.category
            d.uploadDate = dto.uploadDate
            // document → student is a cross-store string FK, not a Core Data
            // relationship. Restore the raw ID unconditionally: requiring the
            // student to already be resolvable here silently dropped the link
            // (the computed `student` accessor tolerates a dangling ID).
            d.studentID = dto.studentID?.uuidString
            d.pdfFileRelativePath = dto.pdfFileRelativePath ?? ""
            viewContext.insert(d)
        }
    }

    // MARK: - Supplies

    static func importSupplies(
        _ dtos: [SupplyDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDSupply>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existing: existing,
            idExtractor: { $0.id },
            entityBuilder: { dto, current in
            let s = current ?? CDSupply(context: viewContext)
            s.id = dto.id
            s.name = dto.name
            s.categoryRaw = (SupplyCategory(rawValue: dto.categoryRaw) ?? .other).rawValue
            s.location = dto.location
            s.currentQuantity = Int64(dto.currentQuantity)
            s.notes = dto.notes
            s.createdAt = dto.createdAt
            s.modifiedAt = dto.modifiedAt
            // Restock (v37+). An older row has none of these: a new staple keeps
            // the defaults, and one already here keeps what it has.
            if let threshold = dto.minimumThreshold { s.minimumThreshold = Int64(threshold) }
            if let unit = dto.unit { s.unit = unit }
            if let level = dto.levelRaw { s.level = RestockLevel(rawValue: level) ?? .stocked }
            if let source = dto.sourceRaw { s.source = RestockSource(rawValue: source) ?? .office }
            if let link = dto.urlString { s.urlString = link }
            if dto.levelRaw != nil {
                s.levelChangedAt = dto.levelChangedAt
                s.levelChangedByID = dto.levelChangedByID
                s.levelChangedByName = dto.levelChangedByName ?? ""
            }
            return s
        })
    }

    // MARK: - Procedures

    static func importProcedures(
        _ dtos: [ProcedureDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDProcedure>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existing: existing,
            idExtractor: { $0.id },
            entityBuilder: { dto, current in
            let p = current ?? CDProcedure(context: viewContext)
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
