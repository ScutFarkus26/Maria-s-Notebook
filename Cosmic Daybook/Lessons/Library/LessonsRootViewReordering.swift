// LessonsRootViewReordering.swift
// Reordering logic for LessonsRootView - extracted for maintainability

import SwiftUI
import CoreData

// MARK: - LessonsRootView Reordering Extension

extension LessonsRootView {

    // MARK: - Sync Reorderable Groups

    func syncReorderableSequences() {
        let ungroupedLabel = "Ungrouped"
        let baseSequences = groupsForSelectedArea
        let hasUngrouped = computeLessonsForArea().contains { $0.sequence.trimmed().isEmpty }

        if let area = selectedArea, !area.trimmed().isEmpty {
            // Include "Ungrouped" in existing groups so its position is preserved by mergeOrder
            let existingWithUngrouped = hasUngrouped ? (baseSequences + [ungroupedLabel]) : baseSequences
            let orderedSequences = FilterOrderStore.loadSequenceOrder(for: area, existing: existingWithUngrouped)
            reorderableSequences = orderedSequences
        } else {
            let allSequences = hasUngrouped ? (baseSequences + [ungroupedLabel]) : baseSequences
            reorderableSequences = allSequences
        }
    }

    // MARK: - Move Groups

    /// Applies a reorder the map expressed as the new order of one area's *visible*
    /// sequence names.
    ///
    /// Sequences the current filter hides never appear in `visibleOrder`, so the new
    /// order is folded into the area's full saved order rather than replacing it.
    func applySequenceOrder(_ visibleOrder: [String], in area: String) {
        let trimmedArea = area.trimmed()
        guard !trimmedArea.isEmpty else { return }

        let saved = helper.groups(for: trimmedArea, lessons: lessons)
        guard let full = FilterOrderStore.applyingVisibleOrder(visibleOrder, to: saved) else { return }

        FilterOrderStore.saveSequenceOrder(full, for: trimmedArea)
        FilterOrderStore.resetCache()
        syncReorderableSequences()
        // The saved sequence order feeds the map's sort.
        refreshLessonsForArea()
    }

    // MARK: - Move Lessons in Area

    /// A lesson dragged onto another in the sequence thread. Moves within the
    /// whole sequence, chips or not (`LessonSequenceOrdering`).
    func moveLessonsInArea(moving movedID: UUID, onto targetID: UUID, sequence: String) {
        guard canReorder else { return }
        let sequenceLessons = lessonsForSequence(sequence, ungroupedLabel: "Ungrouped")
        guard LessonSequenceOrdering.move(movedID, onto: targetID, in: sequenceLessons) else { return }
        rebuildSortIndexForArea()
    }

    // MARK: - Move Single CDLesson Up/Down in Group

    /// Move Earlier / Move Later, renumbering the whole sequence so a tie can't swallow it.
    func moveLessonInSequence(lesson: CDLesson, direction: Int, sequence: String, ungroupedLabel: String) {
        guard canReorder, let lessonID = lesson.id else { return }
        let sequenceLessons = lessonsForSequence(sequence, ungroupedLabel: ungroupedLabel)
        guard LessonSequenceOrdering.step(lessonID, by: direction, in: sequenceLessons) else { return }
        rebuildSortIndexForArea()
    }

    /// Rebuilds `sortIndex` for every lesson in the selected area (the filter chips
    /// don't apply; they used to leave hidden lessons with stale numbers) from the
    /// sequence order and `orderInSequence`, and saves.
    private func rebuildSortIndexForArea() {
        let ungroupedLabel = "Ungrouped"
        let areaLessons = allLessonsInSelectedArea()
        let displaySequences = reorderableSequences.isEmpty
            ? helper.groups(for: selectedArea ?? "", lessons: lessons)
            : reorderableSequences

        var allLessonsInOrder: [CDLesson] = []
        var placed = Set<NSManagedObjectID>()
        for sequence in displaySequences {
            let lessonsInSequence = areaLessons.filter { lesson in
                let lessonSequenceTrimmed = lesson.sequence.trimmed()
                if sequence == ungroupedLabel {
                    return lessonSequenceTrimmed.isEmpty
                } else {
                    return lessonSequenceTrimmed.caseInsensitiveCompare(sequence.trimmed()) == .orderedSame
                }
            }
            let ordered = LessonSequenceOrdering.sorted(lessonsInSequence)
            for lesson in ordered where placed.insert(lesson.objectID).inserted {
                allLessonsInOrder.append(lesson)
            }
        }
        // Any lesson in a sequence the list above doesn't name keeps its place at the end,
        // rather than a number another lesson now has.
        allLessonsInOrder += areaLessons
            .filter { !placed.contains($0.objectID) }
            .sorted { lhs, rhs in
                lhs.sortIndex != rhs.sortIndex
                    ? lhs.sortIndex < rhs.sortIndex
                    : ThreadRowData.lessonSortOrder(lhs, rhs)
            }

        for (idx, lesson) in allLessonsInOrder.enumerated() where lesson.sortIndex != Int64(idx) {
            lesson.sortIndex = Int64(idx)
        }

        saveCoordinator.save(viewContext, reason: "Reorder lessons")
    }

    // MARK: - Move CDLesson to Different Group

    /// The lesson goes to the end of the sub-area it was dropped on. Refused,
    /// moving nothing, when that sub-area already has a lesson by its name.
    func moveLessonToSequence(lesson: CDLesson, newSequence: String) {
        let ungroupedLabel = "Ungrouped"
        let actualGroup = (newSequence == ungroupedLabel) ? "" : newSequence
        let targetLessons = lessonsForSequence(newSequence, ungroupedLabel: ungroupedLabel)
        do {
            try LessonSequenceOrdering.moveToEnd(lesson, ofSequence: actualGroup, after: targetLessons)
        } catch {
            moveRefusal = error.errorDescription
            return
        }
        rebuildSortIndexForArea()
    }

    // MARK: - Insert CDLesson After Another

    /// Repositions a newly-created lesson to sit immediately after `source` in its sequence,
    /// then renumbers `orderInSequence` so the new lesson lands exactly where the user expects.
    func insertLessonAfter(newLesson: CDLesson, after source: CDLesson) {
        guard let sourceID = source.id, let newID = newLesson.id, sourceID != newID else { return }

        let ungroupedLabel = "Ungrouped"
        let sequenceLabel: String = source.sequence.trimmed().isEmpty ? ungroupedLabel : source.sequence

        // `lessonsForSequence` is backed by `@FetchRequest`-derived state; the just-created
        // lesson may or may not be present yet. Filter it out and re-insert positionally so
        // we get the right order either way.
        var inSequence: [CDLesson] = lessonsForSequence(sequenceLabel, ungroupedLabel: ungroupedLabel)
            .filter { $0.id != newID }

        guard let srcIdx = inSequence.firstIndex(where: { $0.id == sourceID }) else { return }

        inSequence.insert(newLesson, at: srcIdx + 1)

        for (idx, lesson) in inSequence.enumerated() {
            lesson.orderInSequence = Int64(idx)
        }

        saveCoordinator.save(viewContext, reason: "Reorder lesson sequence")
    }

    // MARK: - Plan Presentation

    func planPresentation(for lesson: CDLesson, studentIDs: Set<UUID>, purpose: RepeatPurpose? = nil) {
        defer { lessonToSchedule = nil }
        guard let result = Self.filePlan(
            for: lesson, studentIDs: studentIDs, purpose: purpose, in: viewContext
        ) else { return }
        guard result.isNew else {
            ToastService.shared.show(
                PresentationPlanner.alreadyPlannedMessage(purpose: purpose), type: .info, duration: 4
            )
            return
        }
        saveCoordinator.save(viewContext, reason: "Plan presentation")
    }

    /// Files the draft the schedule sheet asked for through the check every
    /// planning path shares, so a child already waiting for the lesson stays
    /// on the plan she's on: planning Maya and Eli when Maya has a draft makes
    /// one for Eli alone. This path matched only a draft naming exactly the
    /// same children, and made Maya a second one (bug hunt 2026-10-12, #32).
    /// Nothing is saved.
    static func filePlan(
        for lesson: CDLesson, studentIDs: Set<UUID>, purpose: RepeatPurpose?, in viewContext: NSManagedObjectContext
    ) -> PresentationPlanner.PlanResult? {
        PresentationPlanner.planOrReuse(lesson: lesson, studentIDs: studentIDs, purpose: purpose, in: viewContext)
    }
}
