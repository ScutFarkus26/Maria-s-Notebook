// ModelRowKinds+Tracks.swift
// The backup row of a lesson sequence's setting, as its hand-written DTO
// wrote and restored it until "Simplify round two", Phase 7 (see
// ModelRowKinds.swift). Tracks, their steps and enrollments were already
// table rows (ModelRowKinds.swift).

import Foundation

public typealias SequenceTrackDTO = ModelRow<SequenceTrackBackupRow>

/// Whether one area's sequence of lessons is taken in order, or switched
/// off. Read leniently: a row without the area or sequence reads it as "",
/// without `isSequential` as in order, without `isExplicitlyDisabled` as on,
/// and without a created date as the moment it is read. A record without an
/// `id` goes out with a new one, as one without a created date goes out
/// dated now. Its link to a track was never backed up, so a restore leaves
/// it as it is.
public enum SequenceTrackBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "SequenceTrack",
        filling: ["createdAt"],
        defaults: [
            "area": .string(""), "sequence": .string(""), "isSequential": .bool(true),
            "isExplicitlyDisabled": .bool(false)
        ],
        nowWhenMissing: ["createdAt"]
    )
}
