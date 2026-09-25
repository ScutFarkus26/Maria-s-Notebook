import Foundation
import Testing
@testable import CosmicDaybook

/// File > New's quick-capture actions and the Album menu's actions are now one
/// object per window, whose handlers the view fills in, instead of a new value
/// of closures per body pass — so the focused value compares equal and the menus
/// are not rebuilt. Every menu item must still reach its own handler, and
/// refilling must take effect without replacing the object.
@Suite("Focused menu actions")
@MainActor
struct FocusedMenuActionsTests {

    private final class Calls {
        var names: [String] = []
    }

    @Test("Each File > New item reaches its own handler, and refilling replaces them in place")
    func quickCaptureDispatch() {
        let actions = QuickCaptureActions()
        let calls = Calls()
        actions.newPresentation()

        func install(_ tag: String) {
            actions.setHandlers(QuickCaptureActions.Handlers(
                newPresentation: { calls.names.append("\(tag)newPresentation") },
                recordPractice: { calls.names.append("\(tag)recordPractice") },
                newTodo: { calls.names.append("\(tag)newTodo") },
                newNote: { calls.names.append("\(tag)newNote") }
            ))
        }
        install("")
        actions.newPresentation()
        actions.recordPractice()
        actions.newTodo()
        actions.newNote()
        install("refilled.")
        actions.newNote()

        #expect(calls.names == [
            "newPresentation", "recordPractice", "newTodo", "newNote", "refilled.newNote"
        ])
    }

    @Test("Each Album menu item reaches its own handler")
    func albumDispatch() {
        let actions = AlbumFocusActions()
        let calls = Calls()
        actions.toggleBookmark()
        #expect(calls.names.isEmpty)

        func record(_ name: String) -> () -> Void { { calls.names.append(name) } }
        actions.install(albumID: "Biology Album.pdf", handlers: AlbumFocusActions.Handlers(
            toggleBookmark: record("toggleBookmark"),
            addNote: record("addNote"),
            nextPage: record("nextPage"),
            previousPage: record("previousPage"),
            zoomIn: record("zoomIn"),
            zoomOut: record("zoomOut"),
            actualSize: record("actualSize"),
            goToPage: record("goToPage"),
            printPDF: record("printPDF"),
            findInAlbum: record("findInAlbum"),
            highlightSelection: record("highlightSelection"),
            exportLesson: record("exportLesson"),
            toggleThumbnails: record("toggleThumbnails")
        ))
        actions.toggleBookmark()
        actions.addNote()
        actions.nextPage()
        actions.previousPage()
        actions.zoomIn()
        actions.zoomOut()
        actions.actualSize()
        actions.goToPage()
        actions.printPDF()
        actions.findInAlbum()
        actions.highlightSelection()
        actions.exportLesson()
        actions.toggleThumbnails()

        #expect(actions.albumID == "Biology Album.pdf")
        #expect(calls.names == [
            "toggleBookmark", "addNote", "nextPage", "previousPage", "zoomIn", "zoomOut", "actualSize",
            "goToPage", "printPDF", "findInAlbum", "highlightSelection", "exportLesson", "toggleThumbnails"
        ])
    }
}
