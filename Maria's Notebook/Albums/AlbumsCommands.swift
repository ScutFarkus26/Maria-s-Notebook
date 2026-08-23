// Menu-bar commands for reading an album. Every item is driven by the
// frontmost album view's focused actions, so they stay disabled everywhere
// else in the notebook.
//
// The standalone Albums app also bound ⌘1–5 for section navigation, ⇧⌘N for
// notes, and ⌘F for find-in-album. Those belong to the notebook (⌘1–7 Go,
// ⇧⌘N New Student, ⌘F global Find), so section navigation lost its shortcuts
// and find-in-album moved to ⌥⌘F.

import SwiftUI

struct AlbumsCommands: Commands {
    @FocusedValue(\.albumActions) private var albumActions

    var body: some Commands {
        CommandMenu("Album") {
            Button("Bookmark This Page") { albumActions?.toggleBookmark() }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(albumActions == nil)
            Button("Add Note to This Page…") { albumActions?.addNote() }
                .disabled(albumActions == nil)
            Button("Highlight Selection") { albumActions?.highlightSelection() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(albumActions == nil)

            Divider()

            Button("Find in Album…") { albumActions?.findInAlbum() }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(albumActions == nil)
            Button("Next Page") { albumActions?.nextPage() }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(albumActions == nil)
            Button("Previous Page") { albumActions?.previousPage() }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(albumActions == nil)
            Button("Go to Page…") { albumActions?.goToPage() }
                .keyboardShortcut("g", modifiers: [.command, .option])
                .disabled(albumActions == nil)

            Divider()

            Button("Zoom In") { albumActions?.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(albumActions == nil)
            Button("Zoom Out") { albumActions?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(albumActions == nil)
            Button("Actual Size") { albumActions?.actualSize() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(albumActions == nil)
            Button("Page Thumbnails") { albumActions?.toggleThumbnails() }
                .keyboardShortcut("t", modifiers: [.command, .option])
                .disabled(albumActions == nil)

            Divider()

            Button("Export Lesson as PDF…") { albumActions?.exportLesson() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(albumActions == nil)
            Button("Print Current Album…") { albumActions?.printPDF() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(albumActions == nil)
        }
    }
}
