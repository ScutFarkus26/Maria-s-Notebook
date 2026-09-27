#if os(iOS)
import CoreData
import Foundation
import PencilKit
import Testing
import UIKit
@testable import CosmicDaybook

/// The album reader saves each page's Pencil ink 800 ms after that page's last
/// change. It used to hold one save task for every page, so any change on page
/// B inside the window cancelled page A's save and page A's ink never reached
/// the store; closing the album dropped whatever was still waiting. On a clock
/// the test moves, so the timing is exact.
@Suite("Album ink saves, page by page")
@MainActor
struct AlbumInkSaveDebouncerTests {

    private static let delay = Duration.milliseconds(800)

    private static func at(_ milliseconds: Int) -> ManualTestClock.Instant {
        ManualTestClock.Instant(offset: .milliseconds(milliseconds))
    }

    /// What the debouncer saved, in order.
    private final class SaveLog {
        var saved: [String] = []
    }

    private static func stroke(from origin: CGFloat) -> PKStroke {
        let points = [CGPoint(x: origin, y: origin), CGPoint(x: origin + 70, y: origin + 50)]
            .enumerated().map { index, location in
                PKStrokePoint(location: location, timeOffset: Double(index) * 0.1,
                              size: CGSize(width: 4, height: 4), opacity: 1, force: 1,
                              azimuth: 0, altitude: .pi / 2)
            }
        return PKStroke(ink: PKInk(.pen, color: .black),
                        path: PKStrokePath(controlPoints: points, creationDate: Date()))
    }

    /// Where each stroke's points lie: what a drawing shows, however it was stored.
    private static func strokeLocations(_ drawing: PKDrawing) -> [[CGPoint]] {
        drawing.strokes.map { $0.path.map(\.location) }
    }

    // MARK: The debouncer

    @Test("Two pages drawn on within the window are both saved, each on its own schedule")
    func twoPagesBothSave() async {
        let clock = ManualTestClock()
        let saves = AlbumInkSaveDebouncer(delay: Self.delay, clock: clock)
        let log = SaveLog()

        saves.schedule(pageIndex: 1) { log.saved.append("page 1") }
        clock.advance(by: .milliseconds(400))
        // The old single task was cancelled here, and page 1 never saved.
        saves.schedule(pageIndex: 2) { log.saved.append("page 2") }
        #expect(await AlbumTestSupport.waitUntil {
            clock.pendingDeadlines == [Self.at(800), Self.at(1200)]
        })
        #expect(log.saved.isEmpty)

        clock.advance(by: .milliseconds(400))
        #expect(await AlbumTestSupport.waitUntil { log.saved == ["page 1"] })
        #expect(saves.pendingPages == [2])
        clock.advance(by: .milliseconds(400))
        #expect(await AlbumTestSupport.waitUntil { log.saved == ["page 1", "page 2"] })
        #expect(saves.pendingPages.isEmpty)
    }

    @Test("A later drawing of the same page replaces the save waiting for it and restarts the wait")
    func laterDrawingSupersedes() async {
        let clock = ManualTestClock()
        let saves = AlbumInkSaveDebouncer(delay: Self.delay, clock: clock)
        let log = SaveLog()

        saves.schedule(pageIndex: 3) { log.saved.append("first stroke") }
        #expect(await AlbumTestSupport.waitUntil { clock.pendingDeadlines == [Self.at(800)] })
        clock.advance(by: .milliseconds(500))
        saves.schedule(pageIndex: 3) { log.saved.append("second stroke") }
        // The first save's wait is cancelled; only the second's is left.
        #expect(await AlbumTestSupport.waitUntil { clock.pendingDeadlines == [Self.at(1300)] })
        #expect(saves.pendingPages == [3])

        clock.advance(by: .milliseconds(300)) // where the first would have saved
        #expect(log.saved.isEmpty)
        clock.advance(by: .milliseconds(500))
        #expect(await AlbumTestSupport.waitUntil { log.saved == ["second stroke"] })
        #expect(saves.pendingPages.isEmpty)
    }

    @Test("Closing the album saves every page still waiting, at once, and nothing twice")
    func flushSavesEverythingWaiting() async {
        let clock = ManualTestClock()
        let saves = AlbumInkSaveDebouncer(delay: Self.delay, clock: clock)
        let log = SaveLog()

        saves.schedule(pageIndex: 4) { log.saved.append("page 4") }
        saves.schedule(pageIndex: 1) { log.saved.append("page 1") }
        #expect(saves.pendingPages == [1, 4])
        // What the reader does on disappearing and on going to the background.
        saves.flush()
        #expect(log.saved == ["page 1", "page 4"])
        #expect(saves.pendingPages.isEmpty)

        // The flushed waits end without saving again; a later page saves alone.
        saves.schedule(pageIndex: 9) { log.saved.append("page 9") }
        clock.advance(by: .seconds(1))
        #expect(await AlbumTestSupport.waitUntil { log.saved.count == 3 })
        #expect(log.saved == ["page 1", "page 4", "page 9"])
    }

    // MARK: Through the reader's ink controller to the store

    /// An ink controller wired as `AlbumDetailView.loadInk()` wires it.
    private static func readerInk(albumID: String,
                                  saves: AlbumInkSaveDebouncer<ManualTestClock>,
                                  context: NSManagedObjectContext) -> InkController {
        let ink = InkController()
        ink.onSave = { pageIndex, drawing in
            saves.schedule(pageIndex: pageIndex) {
                AlbumDetailView.saveInk(drawing, albumID: albumID, pageIndex: pageIndex, in: context)
            }
        }
        return ink
    }

    /// Each stored page's drawing, read back from the store.
    private static func storedInk(albumID: String,
                                  in context: NSManagedObjectContext) throws -> [Int: [[CGPoint]]] {
        var pages: [Int: [[CGPoint]]] = [:]
        for row in AlbumUserDataStore.ink(albumID: albumID, in: context) {
            let data = try #require(row.drawingData)
            pages[Int(row.pageIndex)] = strokeLocations(try PKDrawing(data: data))
        }
        return pages
    }

    @Test("Ink drawn on two pages in quick succession reaches the store for both")
    func twoPagesReachTheStore() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let clock = ManualTestClock()
        let saves = AlbumInkSaveDebouncer(delay: Self.delay, clock: clock)
        let ink = Self.readerInk(albumID: "Math.pdf", saves: saves, context: context)
        let onA = PKDrawing(strokes: [Self.stroke(from: 10)])
        let onB = PKDrawing(strokes: [Self.stroke(from: 40), Self.stroke(from: 90)])

        let pageA = ink.canvas(for: 2)
        let pageB = ink.canvas(for: 3)
        #expect(saves.pendingPages.isEmpty)

        // PencilKit reports a drawing set on a listening canvas as a change,
        // as it does a stroke.
        pageA.drawing = onA
        clock.advance(by: .milliseconds(300))
        pageB.drawing = onB
        #expect(saves.pendingPages == [2, 3])
        clock.advance(by: .milliseconds(500))
        #expect(await AlbumTestSupport.waitUntil { saves.pendingPages == [3] })
        clock.advance(by: .milliseconds(300))
        #expect(await AlbumTestSupport.waitUntil { saves.pendingPages.isEmpty })

        let stored = try Self.storedInk(albumID: "Math.pdf", in: context)
        #expect(stored == [2: Self.strokeLocations(onA), 3: Self.strokeLocations(onB)])
    }

    @Test("Closing the album mid-wait stores the page's latest drawing at once")
    func closingStoresTheLatestDrawing() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let clock = ManualTestClock()
        let saves = AlbumInkSaveDebouncer(delay: Self.delay, clock: clock)
        let ink = Self.readerInk(albumID: "Math.pdf", saves: saves, context: context)
        let canvas = ink.canvas(for: 6)
        let firstStroke = PKDrawing(strokes: [Self.stroke(from: 10)])
        let twoStrokes = PKDrawing(strokes: [Self.stroke(from: 10), Self.stroke(from: 60)])

        canvas.drawing = firstStroke
        canvas.drawing = twoStrokes
        #expect(saves.pendingPages == [6])
        #expect(AlbumUserDataStore.ink(albumID: "Math.pdf", in: context).isEmpty)

        saves.flush()
        let stored = try Self.storedInk(albumID: "Math.pdf", in: context)
        #expect(stored == [6: Self.strokeLocations(twoStrokes)])
    }

    /// Why a page's first canvas now takes its drawing before the delegate:
    /// PencilKit reports a drawing assigned to a listening canvas as a change,
    /// and each change is a save, so with saves per page every page shown
    /// would have saved its unchanged ink.
    private final class ChangeCounter: NSObject, PKCanvasViewDelegate {
        var changes = 0
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) { changes += 1 }
    }

    @Test("PencilKit reports a drawing assigned after the delegate as a change, and one assigned before as none")
    func assignmentOrderDecidesTheReport() {
        let drawing = PKDrawing(strokes: [Self.stroke(from: 10)])
        let counter = ChangeCounter()
        let listening = PKCanvasView()
        listening.delegate = counter
        listening.drawing = drawing
        #expect(counter.changes == 1)

        let loadedFirst = PKCanvasView()
        loadedFirst.drawing = drawing
        loadedFirst.delegate = counter
        #expect(counter.changes == 1)
    }
}
#endif
