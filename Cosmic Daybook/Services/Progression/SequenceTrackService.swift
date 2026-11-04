import Foundation
import CoreData

/// Reads over the track entities, for the screens that still show them.
///
/// Since 2026-11-03 nothing writes a track, a step or an enrollment: the four
/// entities are an older copy of what the lesson sequences and the Year Plan
/// carry, and `docs/Plans/Plan - Retire the track entities.md` takes them out
/// over two roll-outs. A track is still found by its title, "Area — Sequence".
struct SequenceTrackService {

    /// The track for an area/sequence pair, by title.
    static func cdGetTrack(
        area: String,
        sequence: String,
        context: NSManagedObjectContext
    ) throws -> CDTrackEntity? {
        let trimmedArea = area.trimmed()
        let trimmedSequence = sequence.trimmed()
        let trackTitle = "\(trimmedArea) — \(trimmedSequence)"
        let allTracks = trackCandidates(title: trackTitle, context: context)
        return preferredTrack(among: allTracks.filter { $0.title.trimmed() == trackTitle })
    }

    /// The twin to read when a title is defined more than once: the one with
    /// steps, then the one linked to its sequence track, then the oldest.
    /// The launch-time merge (`DataCleanupService.mergeSameTitleTracks`)
    /// folds twins onto the oldest by CloudKit creation; until it has run
    /// on every device this keeps each lookup landing on the same copy
    /// instead of whichever an unsorted fetch returned first.
    static func preferredTrack(among candidates: [CDTrackEntity]) -> CDTrackEntity? {
        candidates.min { lhs, rhs in
            let lhsSteps = lhs.steps?.count ?? 0
            let rhsSteps = rhs.steps?.count ?? 0
            if (lhsSteps > 0) != (rhsSteps > 0) { return lhsSteps > 0 }
            if (lhs.sequenceTrack != nil) != (rhs.sequenceTrack != nil) { return lhs.sequenceTrack != nil }
            let lhsCreated = lhs.createdAt ?? .distantFuture
            let rhsCreated = rhs.createdAt ?? .distantFuture
            if lhsCreated != rhsCreated { return lhsCreated < rhsCreated }
            return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
        }
    }
}
