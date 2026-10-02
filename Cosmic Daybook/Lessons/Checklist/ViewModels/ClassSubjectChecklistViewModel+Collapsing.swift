// ClassAreaChecklistViewModel+Collapsing.swift
// Sequence bands the guide folds away. Remembered per area; a lesson search shows
// every band open, so a match is never hidden behind a fold.

import Foundation

extension ClassAreaChecklistViewModel {

    /// True while the lesson search narrows the rows. Bands draw open then.
    var isSearchingLessons: Bool { !lessonQueryTokens.isEmpty }

    /// Whether `sequence`'s lessons are hidden under its band right now.
    func isCollapsed(_ sequence: String) -> Bool {
        !isSearchingLessons && collapsedSequences.contains(ChecklistCollapsedSequences.key(for: sequence))
    }

    /// True when every visible band is folded: the corner offers "Expand all" then.
    var areAllSequencesCollapsed: Bool {
        !visibleSequences.isEmpty && visibleSequences.allSatisfy(isCollapsed)
    }

    func toggleCollapsed(_ sequence: String) {
        let key = ChecklistCollapsedSequences.key(for: sequence)
        if collapsedSequences.contains(key) {
            collapsedSequences.remove(key)
        } else {
            collapsedSequences.insert(key)
        }
        saveCollapsedSequences()
    }

    /// Folds every band in the area, or opens them all.
    func setAllSequencesCollapsed(_ collapsed: Bool) {
        collapsedSequences = collapsed
            ? Set(orderedSequences.map(ChecklistCollapsedSequences.key(for:)))
            : []
        saveCollapsedSequences()
    }

    /// Opens `sequence`'s band. Returns true when it was folded.
    @discardableResult
    func expandSequence(_ sequence: String) -> Bool {
        guard collapsedSequences.remove(ChecklistCollapsedSequences.key(for: sequence)) != nil else {
            return false
        }
        saveCollapsedSequences()
        return true
    }

    /// Opens the band holding `lessonID`, for a deep link to its row. Returns true when
    /// it was folded, so the caller knows to wait a beat for the rows to draw.
    @discardableResult
    func expandSequence(containing lessonID: UUID) -> Bool {
        guard let sequence = sequence(containing: lessonID) else { return false }
        return expandSequence(sequence)
    }

    /// The visible band `lessonID` draws under ("" for Other), as `visibleSequences` spells it.
    func sequence(containing lessonID: UUID) -> String? {
        guard let lesson = visibleLessons.first(where: { $0.id == lessonID }) else { return nil }
        let own = ChecklistCollapsedSequences.key(for: lesson.sequence)
        return visibleSequences.first { ChecklistCollapsedSequences.key(for: $0) == own }
    }

    private func saveCollapsedSequences() {
        ChecklistCollapsedSequences.save(
            collapsedSequences, area: selectedArea, defaults: collapsedSequencesDefaults
        )
    }
}
