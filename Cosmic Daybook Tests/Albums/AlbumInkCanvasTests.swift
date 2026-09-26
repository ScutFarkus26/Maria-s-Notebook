#if os(iOS)
import Foundation
import PencilKit
import Testing
import UIKit
@testable import CosmicDaybook

/// PDFKit asks for a Pencil canvas for every album page it shows. An empty
/// canvas no tool has touched is dropped when its page scrolls away and
/// rebuilt if the page comes back; a canvas with ink, or one drawn on since
/// the album opened, stays so its Pencil undo history does too.
@Suite("Album ink canvases")
@MainActor
struct AlbumInkCanvasTests {

    private static func stroke() -> PKStroke {
        let points = [CGPoint(x: 10, y: 10), CGPoint(x: 80, y: 60)].enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: Double(index) * 0.1,
                          size: CGSize(width: 4, height: 4), opacity: 1, force: 1,
                          azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black),
                        path: PKStrokePath(controlPoints: points, creationDate: Date()))
    }

    // MARK: The rule

    @Test("An empty canvas no tool has touched is dropped")
    func emptyUnusedCanvasIsDropped() {
        #expect(InkController.dropsCanvas(strokeCount: 0, wasUsed: false))
    }

    @Test("A canvas with strokes is kept")
    func inkedCanvasIsKept() {
        #expect(!InkController.dropsCanvas(strokeCount: 1, wasUsed: false))
        #expect(!InkController.dropsCanvas(strokeCount: 12, wasUsed: true))
    }

    @Test("A canvas drawn on and erased back to empty is kept, with its undo history")
    func erasedCanvasIsKept() {
        #expect(!InkController.dropsCanvas(strokeCount: 0, wasUsed: true))
    }

    // MARK: The controller

    @Test("Reading through 300 empty pages leaves only the canvas on screen")
    func scrollingDropsEmptyCanvases() {
        let ink = InkController()
        for page in 0..<300 {
            let canvas = ink.canvas(for: page)
            #expect(canvas.tag == page)
            // The page before scrolls away as this one arrives.
            if page > 0 { ink.canvasDidEndDisplaying(ink.canvas(for: page - 1)) }
        }
        #expect(ink.canvases.count == 1)
    }

    @Test("Inked and drawn-on canvases survive scrolling away; saved ink is untouched")
    func inkedAndUsedCanvasesAreKept() {
        let ink = InkController()
        let saved = PKDrawing(strokes: [Self.stroke()])
        ink.drawings = [4: saved]
        let inked = ink.canvas(for: 4)
        let used = ink.canvas(for: 5)
        ink.canvasViewDidBeginUsingTool(used)
        let untouched = ink.canvas(for: 6)

        ink.canvasDidEndDisplaying(inked)
        ink.canvasDidEndDisplaying(used)
        ink.canvasDidEndDisplaying(untouched)

        #expect(ink.canvas(for: 4) === inked)
        #expect(ink.canvas(for: 5) === used)
        #expect(ink.canvas(for: 6) !== untouched)
        #expect(ink.drawings[4] == saved)
        #expect(ink.canvas(for: 4).drawing == saved)
    }

    @Test("A rebuilt canvas starts from the page's drawing and follows markup mode")
    func rebuiltCanvasMatchesTheOriginal() {
        let ink = InkController()
        ink.markupEnabled = true
        let first = ink.canvas(for: 2)
        ink.canvasDidEndDisplaying(first)
        let rebuilt = ink.canvas(for: 2)
        #expect(rebuilt !== first)
        #expect(rebuilt.isUserInteractionEnabled)
        #expect(rebuilt.drawing.strokes.isEmpty)
        ink.markupEnabled = false
        #expect(!rebuilt.isUserInteractionEnabled)
    }

    @Test("A rebuilt canvas reports no drawing change, so it schedules no ink save")
    func rebuiltCanvasSchedulesNoSave() {
        let ink = InkController()
        var reported: [Int] = []
        ink.onSave = { pageIndex, _ in reported.append(pageIndex) }
        let first = ink.canvas(for: 3)
        // Whatever the first canvas reported is how it has always behaved;
        // the page's old canvas came back without reporting anything.
        let reportedByFirst = reported.count
        ink.canvasDidEndDisplaying(first)
        _ = ink.canvas(for: 3)
        #expect(reported.count == reportedByFirst)
    }

    @Test("A canvas PDFKit shows again without asking for a new one is taken back")
    func redisplayedCanvasIsTracked() {
        let ink = InkController()
        let canvas = ink.canvas(for: 7)
        ink.canvasDidEndDisplaying(canvas)
        #expect(ink.canvases[7] == nil)
        ink.markupEnabled = true
        ink.canvasWillDisplay(canvas)
        #expect(ink.canvases[7] === canvas)
        #expect(canvas.isUserInteractionEnabled)
    }
}
#endif
