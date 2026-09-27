import Foundation
import CoreData
import OSLog

// MARK: - CDTrackEntity/Group Imports

extension BackupEntityImporter {

    // MARK: - Group Tracks

    static func importSequenceTracks(
        _ dtos: [SequenceTrackDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDSequenceTrack>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existing: existing,
            idExtractor: { $0.id },
            entityBuilder: { dto, current in
            let g = current ?? CDSequenceTrack(context: viewContext)
            g.id = dto.id
            g.area = dto.area
            g.sequence = dto.sequence
            g.isSequential = dto.isSequential
            g.isExplicitlyDisabled = dto.isExplicitlyDisabled
            g.createdAt = dto.createdAt
            return g
        })
    }
}
