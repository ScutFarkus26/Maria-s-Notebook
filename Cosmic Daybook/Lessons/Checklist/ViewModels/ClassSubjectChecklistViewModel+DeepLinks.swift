// ClassAreaChecklistViewModel+DeepLinks.swift
// Requests from elsewhere to open the grid somewhere particular: one lesson's
// row ("Show in Checklist" on a presentation card), or an area and one of its
// sequence bands ("View Class Progress" on a child's track card).

import CoreData
import Foundation

extension ClassAreaChecklistViewModel {

    /// Takes the deep link the router is holding, if any, ahead of the area's
    /// lessons loading. Returns the sequence it asked for, to reveal once they
    /// have (`requestSequenceJump`). The lesson request is checked first: it
    /// names an exact row, so it outranks a plain area jump and the persisted
    /// area alike.
    func consumeDeepLink(from router: AppRouter) -> String? {
        if let request = router.consumeChecklistLessonRequest() {
            let area = request.area.trimmed()
            if !area.isEmpty { selectedArea = area }
            // A text filter carried over from a previous visit is free to hide
            // the very row being revealed. The lessons' refresh re-applies the
            // filters, so clearing the fields is enough here.
            clearLessonQueryFields()
            focusedLessonID = request.lessonID
            return nil
        }
        guard let filterArea = router.checklistFilterArea else { return nil }
        let sequence = router.checklistFilterSequence
        selectedArea = filterArea
        router.checklistFilterArea = nil
        router.checklistFilterSequence = nil
        // The same goes for the band: a carried-over search could hide it.
        if sequence != nil { clearLessonQueryFields() }
        return sequence
    }

    /// Asks the grid to open on `sequence`'s band, as Jump to Sequence does.
    /// The sequence used to be dropped, so a Geometry track card opened all
    /// of Math at the top.
    func requestSequenceJump(_ sequence: String) {
        pendingSequenceJump = visibleSequence(matching: sequence)
    }

    /// The band `name` means, as `visibleSequences` spells it, or nil. A
    /// request from a track's title may differ in case or stray spaces.
    func visibleSequence(matching name: String) -> String? {
        if visibleSequences.contains(name) { return name }
        let wanted = name.trimmed()
        guard !wanted.isEmpty else { return nil }
        return visibleSequences.first { $0.trimmed().caseInsensitiveCompare(wanted) == .orderedSame }
    }

    private func clearLessonQueryFields() {
        lessonQuery = ""
        appliedLessonQuery = ""
        lessonQueryTokens = []
    }
}
