import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// `SequenceTrackService` only reads now (2026-11-03): nothing enrolls a
/// child or rebuilds a track's steps. What is left to pin is that a track is
/// still found by its title on the store the app really runs on.
@Suite("Sequence Track Service lookups")
@MainActor
struct SequenceTrackServiceScopeTests {

    @Test("On SQLite, a padded title still resolves to its track")
    func sqliteLookupFoldsWhitespace() throws {
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        let track = CDTrackEntity(context: context)
        track.title = " Math — Chains "
        let other = CDTrackEntity(context: context)
        other.title = "Math — Fractions"
        try context.save()
        context.reset()

        let foundTrack = try SequenceTrackService.cdGetTrack(area: "Math", sequence: "Chains", context: context)
        #expect(foundTrack?.objectID == track.objectID)
        #expect(try SequenceTrackService.cdGetTrack(area: "Math", sequence: "Beads", context: context) == nil)
    }
}
