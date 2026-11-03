import Foundation

// MARK: - How a run of Set Up Classroom Sharing starts
//
// From what the server and this device hold: make the share, go on with the
// pinned one, pin a share no pin names (bug hunt 2026-11-02, #31), or refuse.
// Its own file so `ClassroomSharingService+Setup` stays within its length.

extension ClassroomSharingService {

    /// How a run of setup starts (`setupStart`).
    enum SetupStart: Equatable {
        /// No share anywhere: make one.
        case create
        /// Go on with the pinned share, alone on the server.
        case resume(zone: String)
        /// Pin the share in `zone`, which no pin names, and go on with it.
        case adopt(zone: String)
        case refuse(ClassroomShareError)
    }

    /// How setup starts, from the share zones on the server, the zones of the
    /// shares the private store holds, and the pinned zone.
    ///
    /// One share zone on the server, its share here, and no pin naming it
    /// (none, or one naming a zone that's gone) is a setup that stopped
    /// between making the share and saving its pin: the app quit in between.
    /// Nothing else could ever pin it, and every later setup refused for the
    /// zone it found (bug hunt 2026-11-02, #31), so setup pins it and goes on.
    /// A share zone whose share hasn't downloaded here is never adopted: there
    /// is nothing here to pin.
    static func setupStart(serverZones: Set<String>, localShareZones: [String], pinnedZone: String?) -> SetupStart {
        if let pinnedZone, localShareZones.contains(pinnedZone) {
            return serverZones == [pinnedZone]
                ? .resume(zone: pinnedZone)
                : .refuse(.otherShareZonesExist(serverZones.count))
        }
        if let pinnedZone, serverZones.contains(pinnedZone) { return .refuse(.shareStillSyncing) }
        if serverZones.isEmpty, localShareZones.isEmpty { return .create }
        if serverZones.count == 1, localShareZones.count == 1, let zone = localShareZones.first,
           serverZones.contains(zone) {
            return .adopt(zone: zone)
        }
        return .refuse(.otherShareZonesExist(max(serverZones.count, localShareZones.count)))
    }
}
