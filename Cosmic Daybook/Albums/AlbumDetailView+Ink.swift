// AlbumDetailView+Ink.swift
// The album reader's Pencil ink (iOS): the album's saved drawings loaded into
// the canvases, and each change saved for its own page.

import CoreData
import SwiftUI
#if os(iOS)
import PencilKit
#endif

extension AlbumDetailView {

    func loadInk() {
        #if os(iOS)
        var drawings: [Int: PKDrawing] = [:]
        for item in AlbumUserDataStore.ink(albumID: album.id, in: context) {
            if let data = item.drawingData, let drawing = try? PKDrawing(data: data) {
                drawings[Int(item.pageIndex)] = drawing
            }
        }
        ink.drawings = drawings
        ink.onSave = { pageIndex, drawing in
            scheduleInkSave(pageIndex: pageIndex, drawing: drawing)
        }
        #endif
    }

    #if os(iOS)
    /// Per page: a drawing on one page never cancels another page's save.
    private func scheduleInkSave(pageIndex: Int, drawing: PKDrawing) {
        let albumID = album.id
        inkSaves.schedule(pageIndex: pageIndex) {
            Self.saveInk(drawing, albumID: albumID, pageIndex: pageIndex, in: context)
        }
    }

    /// Writes one page's drawing; an erased page drops its row.
    static func saveInk(_ drawing: PKDrawing, albumID: String, pageIndex: Int,
                        in context: NSManagedObjectContext) {
        let data = drawing.strokes.isEmpty ? Data() : drawing.dataRepresentation()
        AlbumUserDataStore.saveInk(albumID: albumID, pageIndex: pageIndex,
                                   drawingData: data, in: context)
    }
    #endif
}
