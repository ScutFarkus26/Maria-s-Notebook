// ModelRowKinds+Albums.swift
// The backup rows of a teaching album's highlights and Pencil ink (format
// v21+), as their hand-written DTOs wrote and restored them until "Simplify
// round two", Phase 7 (see ModelRowKinds.swift). Bookmarks, page notes,
// recent visits and reading positions were already table rows
// (ModelRowKinds.swift).
//
// The rest of the backup leaves binary attributes out by design, because they
// can be made again (thumbnails, covers, file bookmarks: see
// ModelRowKinds+Resources). Highlights and ink are the exception: nothing can
// make them again, so losing them on restore would be real loss. A
// highlight's rectangles travel as plain numbers, and ink as its PencilKit
// drawing data.

import CoreData
import Foundation

public typealias AlbumHighlightDTO = ModelRow<AlbumHighlightBackupRow>
public typealias AlbumPageInkDTO = ModelRow<AlbumPageInkBackupRow>

/// A passage highlighted on an album page. `rects` carries the page-space
/// rectangles kept in `rectsData`, each as [x, y, width, height] (a blob that
/// won't decode goes out as none); they restore through `setRectValues`,
/// which drops any that isn't four numbers. A record without an `id` goes out
/// with a new one, as one without a created or changed date goes out dated now.
public enum AlbumHighlightBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "AlbumHighlight",
        filling: ["createdAt", "modifiedAt"],
        omitting: ["rectsData"],
        computed: [
            .computed(
                "rects", .doubleArrays, of: CDAlbumHighlight.self, required: true,
                read: { .doubleArrays($0.rectValues) },
                write: { highlight, value, _ in
                    guard case .doubleArrays(let rects)? = value else { return }
                    highlight.setRectValues(rects)
                }
            )
        ]
    )
}

/// The ink on one album page. Every row has `drawingData`: a page without
/// ink goes out with none (empty data), which restores as no drawing. A
/// record without an `id` goes out with a new one, as one without a changed
/// date goes out dated now.
public enum AlbumPageInkBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "AlbumPageInk",
        filling: ["modifiedAt"],
        computed: [
            .computed(
                "drawingData", .data, of: CDAlbumPageInk.self, required: true,
                read: { .data($0.drawingData ?? Data()) },
                write: { ink, value, _ in
                    guard case .data(let drawing)? = value else { return }
                    ink.drawingData = drawing.isEmpty ? nil : drawing
                }
            )
        ]
    )
}
