import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-29, #21: the note editor closed without asking after the
/// children, tags, "Include in report" or "Needs follow-up" were changed, and
/// lost them. Its unsaved check looked only at the text and photo; it now
/// compares everything Save writes (`NoteEditorSave.Edit`).
@Suite("Note editor's unsaved check (fix 10-29 #21)")
@MainActor
struct NoteEditorUnsavedFix1029Tests {

    private let maya = UUID()
    private let etty = UUID()

    private var opened: NoteEditorSave.Edit {
        NoteEditorSave.Edit(
            body: "Maya counted to 100.",
            children: [maya],
            tags: ["Math"],
            includeInReport: false,
            needsFollowUp: false,
            imagePath: nil
        )
    }

    @Test("Nothing changed, or only space around the text, is nothing to lose")
    func unchanged() {
        var edit = opened
        #expect(edit == opened)
        edit.body = "  Maya counted to 100.\n"
        #expect(edit == opened)
    }

    @Test("A change to any field Save writes is something to lose")
    func everyFieldCounts() {
        var children = opened
        children.children = [maya, etty]
        var tags = opened
        tags.tags = ["Math", "Practical Life"]
        var report = opened
        report.includeInReport = true
        var followUp = opened
        followUp.needsFollowUp = true
        var text = opened
        text.body = "Maya counted to 1,000."
        var photo = opened
        photo.imagePath = "photo.jpg"

        for edit in [children, tags, report, followUp, text, photo] {
            #expect(edit != opened)
        }
    }
}
