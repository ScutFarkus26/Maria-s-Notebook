import SwiftUI

/// What every tile on the day shares, worked out once per redraw of the grid
/// rather than once for each of its 22 tiles: whether the day is ahead, the
/// menu's statuses, and who she is, which `markerName` compares each mark
/// with (two settings reads) (bug hunt 2026-11-03, #3).
struct AssistantTileDay {
    let isFuture: Bool
    let menuStatuses: [AttendanceStatus]
    let canMark: Bool
    let myRecordName: String?
    let myName: String?
    let guideName: String?

    init(viewModel: AssistantAttendanceViewModel, guideName: String?) {
        isFuture = viewModel.isFuture
        menuStatuses = viewModel.menuStatuses
        canMark = viewModel.canMark
        myRecordName = ClassroomIdentity.currentUserRecordName
        myName = ClassroomIdentity.displayName
        self.guideName = guideName
    }
}

/// A grid tile that SwiftUI draws again only when something it shows has
/// changed. A tile's closures can't be compared, so without this one child's
/// mark, or any import, drew all 22 tiles again (bug hunt 2026-11-03, #3).
/// The closures act through the row and the view model, both compared here,
/// so a tile kept as it was still does what a new one would.
struct AssistantGridTile: View, Equatable {
    let tile: AttendanceTile
    /// The view model the tile's closures act on.
    let model: ObjectIdentifier

    static func == (lhs: Self, rhs: Self) -> Bool {
        let old = lhs.tile
        let new = rhs.tile
        return lhs.model == rhs.model && old.row == new.row && old.tapTarget == new.tapTarget
            && old.tapHint == new.tapHint && old.spokenTapHint == new.spokenTapHint
            && old.menuStatuses == new.menuStatuses && old.canMark == new.canMark
            && old.usesShortName == new.usesShortName && old.height == new.height && old.markedBy == new.markedBy
            && (old.onPickup == nil) == (new.onPickup == nil) && (old.onBack == nil) == (new.onBack == nil)
            && old.rippleTrigger == new.rippleTrigger && old.rippleDelay == new.rippleDelay
    }

    var body: some View { tile }
}
