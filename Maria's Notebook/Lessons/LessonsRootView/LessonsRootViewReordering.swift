// LessonsRootViewReordering.swift
// Reordering logic for LessonsRootView - extracted for maintainability

import SwiftUI
import CoreData
import OSLog

private let logger = Logger.lessons

// MARK: - LessonsRootView Reordering Extension

extension LessonsRootView {

    // MARK: - Sync Reorderable Groups

    func syncReorderableSequences() {
        let ungroupedLabel = "Ungrouped"
        let baseSequences = groupsForSelectedArea
        let hasUngrouped = lessonsForArea.contains { $0.sequence.trimmed().isEmpty }

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

    @MainActor
    func moveSequences(from source: IndexSet, to destination: Int, in groups: [String], overrideArea: String? = nil) {
        let area = overrideArea ?? selectedArea ?? ""
        guard !area.trimmed().isEmpty else { return }
        guard let sourceIndex = source.first else { return }
        guard sourceIndex < groups.count else { return }

        var reordered = groups
        reordered.move(fromOffsets: source, toOffset: destination)

        reorderableSequences = reordered

        // Save the full order including "Ungrouped" so its position is preserved
        FilterOrderStore.saveSequenceOrder(reordered, for: area)
        FilterOrderStore.resetCache()
    }

    // MARK: - Move Group Up/Down

    @MainActor
    func moveSequenceUpDown(sequence: String, direction: Int, in groups: [String]) {
        guard let area = selectedArea, !area.trimmed().isEmpty else { return }
        guard let index = groups.firstIndex(of: sequence) else { return }

        let target = index + direction
        guard target >= 0, target < groups.count else { return }

        var reordered = groups
        reordered.swapAt(index, target)

        reorderableSequences = reordered
        FilterOrderStore.saveSequenceOrder(reordered, for: area)
        FilterOrderStore.resetCache()
    }

    // MARK: - Move Lessons in Area

    @MainActor
    func moveLessonsInArea(from source: IndexSet, to destination: Int, in groupLessons: [CDLesson]) {
        guard canReorder else { return }
        guard let area = selectedArea, !area.trimmed().isEmpty else { return }
        guard let sourceIndex = source.first else { return }
        guard sourceIndex < groupLessons.count else { return }

        var reorderedSequence: [CDLesson] = groupLessons
        reorderedSequence.move(fromOffsets: source, toOffset: destination)

        for (idx, lesson) in reorderedSequence.enumerated() {
            lesson.orderInSequence = Int64(idx)
        }

        let ungroupedLabel: String = "Ungrouped"
        let displaySequences: [String] = reorderableSequences.isEmpty
            ? helper.groups(for: area, lessons: Array(lessons))
            : reorderableSequences
        let allLessonsInOrder: [CDLesson] = collectOrderedLessons(
            displaySequences: displaySequences,
            ungroupedLabel: ungroupedLabel
        )

        for (idx, lesson) in allLessonsInOrder.enumerated() {
            lesson.sortIndex = Int64(idx)
        }

        do {
            try viewContext.save()
        } catch {
            logger.error("Failed to save lesson reorder: \(error)")
        }
    }

    private func collectOrderedLessons(displaySequences: [String], ungroupedLabel: String) -> [CDLesson] {
        var result: [CDLesson] = []
        for sequence in displaySequences {
            let trimmedSequence: String = sequence.trimmed()
            let lessonsInSequence: [CDLesson] = lessonsForArea.filter { (lesson: CDLesson) -> Bool in
                let lessonSequenceTrimmed: String = lesson.sequence.trimmed()
                if sequence == ungroupedLabel {
                    return lessonSequenceTrimmed.isEmpty
                } else {
                    return lessonSequenceTrimmed.caseInsensitiveCompare(trimmedSequence) == .orderedSame
                }
            }.sorted { (lhs: CDLesson, rhs: CDLesson) -> Bool in
                if lhs.orderInSequence != rhs.orderInSequence {
                    return lhs.orderInSequence < rhs.orderInSequence
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            result.append(contentsOf: lessonsInSequence)
        }
        return result
    }

    // MARK: - Move Single CDLesson Up/Down in Group

    @MainActor
    func moveLessonInSequence(lesson: CDLesson, direction: Int, sequence: String, ungroupedLabel: String) {
        guard canReorder else { return }

        let groupLessons = lessonsForSequence(sequence, ungroupedLabel: ungroupedLabel)
        guard let index = groupLessons.firstIndex(where: { $0.id == lesson.id }) else { return }

        let target = index + direction
        guard target >= 0, target < groupLessons.count else { return }

        // Swap orderInSequence between the two lessons
        let neighbor = groupLessons[target]
        let tempOrder = lesson.orderInSequence
        lesson.orderInSequence = neighbor.orderInSequence
        neighbor.orderInSequence = tempOrder

        // Rebuild sortIndex across the entire area
        rebuildSortIndexForArea()
    }

    /// Rebuilds `sortIndex` for all lessons in the selected area based on sequence order and `orderInSequence`.
    @MainActor
    private func rebuildSortIndexForArea() {
        let ungroupedLabel = "Ungrouped"
        let displaySequences = reorderableSequences

        var allLessonsInOrder: [CDLesson] = []
        for sequence in displaySequences {
            let lessonsInSequence = lessonsForArea.filter { lesson in
                let lessonSequenceTrimmed = lesson.sequence.trimmed()
                if sequence == ungroupedLabel {
                    return lessonSequenceTrimmed.isEmpty
                } else {
                    return lessonSequenceTrimmed.caseInsensitiveCompare(sequence.trimmed()) == .orderedSame
                }
            }.sorted { lhs, rhs in
                if lhs.orderInSequence != rhs.orderInSequence {
                    return lhs.orderInSequence < rhs.orderInSequence
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            allLessonsInOrder.append(contentsOf: lessonsInSequence)
        }

        for (idx, lesson) in allLessonsInOrder.enumerated() {
            lesson.sortIndex = Int64(idx)
        }

        do {
            try viewContext.save()
        } catch {
            logger.error("Failed to save lesson reorder: \(error)")
        }
    }

    // MARK: - Move CDLesson to Different Group

    @MainActor
    func moveLessonToSequence(lesson: CDLesson, newSequence: String) {
        let ungroupedLabel = "Ungrouped"
        let actualGroup = (newSequence == ungroupedLabel) ? "" : newSequence

        lesson.sequence = actualGroup

        // Set orderInSequence to end of target sequence
        let targetLessons = lessonsForSequence(newSequence, ungroupedLabel: ungroupedLabel)
        let maxOrder = targetLessons.map(\.orderInSequence).max() ?? -1
        lesson.orderInSequence = maxOrder + 1

        rebuildSortIndexForArea()
    }

    // MARK: - Reorder Section by Drag

    /// Move a section block within its sequence. Persists the new section order via
    /// `FilterOrderStore` (so Plan/Cards/List views update) and rewrites `orderInSequence`
    /// on the affected lessons so flat views (Browse) reflect the same order.
    @MainActor
    func reorderSectionByDrag(sequence: String, source: String, target: String) {
        guard let area = selectedArea, !area.trimmed().isEmpty else { return }
        guard source != target else { return }

        let groupLessons = lessonsForSequence(sequence, ungroupedLabel: "Ungrouped")
        let existingNonEmpty: [String] = Array(Set(
            groupLessons.map { $0.section.trimmed() }.filter { !$0.isEmpty }
        )).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        var order = FilterOrderStore.loadSectionOrder(for: area, sequence: sequence, existing: existingNonEmpty)
        order.removeAll { $0 == source }
        if let targetIdx = order.firstIndex(of: target) {
            order.insert(source, at: targetIdx)
        } else {
            order.append(source)
        }

        FilterOrderStore.saveSectionOrder(order, for: area, sequence: sequence)
        FilterOrderStore.resetCache()

        // Propagate to flat views: rewrite orderInSequence so lessons under the moved
        // section sit contiguously in the new position. Within each section,
        // preserve current orderInSequence sort.
        let bySection = Dictionary(grouping: groupLessons) { $0.section.trimmed() }
        var idx: Int64 = 0
        let fullOrder: [String] = order + (bySection.keys.contains("") ? [""] : [])
        for sh in fullOrder {
            let lessons = (bySection[sh] ?? []).sorted { lhs, rhs in
                if lhs.orderInSequence != rhs.orderInSequence { return lhs.orderInSequence < rhs.orderInSequence }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            for lesson in lessons {
                lesson.orderInSequence = idx
                idx += 1
            }
        }

        rebuildSortIndexForArea()
    }

    // MARK: - Insert CDLesson After Another

    /// Repositions a newly-created lesson to sit immediately after `source` in its sequence,
    /// then renumbers `orderInSequence` so the new lesson lands exactly where the user expects.
    @MainActor
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

        do {
            try viewContext.save()
        } catch {
            logger.error("Failed to save lesson after insert-after: \(error)")
        }
    }

    // MARK: - Move CDLesson to Different Section

    @MainActor
    func moveLessonToSection(lesson: CDLesson, newSection: String) {
        lesson.section = newSection

        do {
            try viewContext.save()
        } catch {
            logger.error("Failed to save lesson section change: \(error)")
        }
    }

    // MARK: - Plan Presentation

    func planPresentation(for lesson: CDLesson, studentIDs: Set<UUID>) {
        guard !studentIDs.isEmpty else { return }

        // NOTE: SwiftData #Predicate doesn't support capturing local Array/Set variables,
        // so we fetch all and filter in memory
        let allStudents: [CDStudent]
        do {
            allStudents = try viewContext.fetch(NSFetchRequest<CDStudent>(entityName: "Student"))
        } catch {
            logger.warning("Failed to fetch students: \(error)")
            allStudents = []
        }
        let students = allStudents.filter {
            guard let sid = $0.id else { return false }
            return studentIDs.contains(sid)
        }

        let lessonIDString = lesson.id?.uuidString ?? ""
        let draftRaw = LessonAssignmentState.draft.rawValue
        let existingPredicate = NSPredicate(
            format: "lessonID == %@ AND stateRaw == %@",
            lessonIDString as CVarArg,
            draftRaw as CVarArg
        )
        let existingDescriptor = {
            let r = NSFetchRequest<CDLessonAssignment>(entityName: "LessonAssignment")
            r.predicate = existingPredicate
            return r
        }()
        let existingAssignments: [CDLessonAssignment]
        do {
            existingAssignments = try viewContext.fetch(existingDescriptor)
        } catch {
            logger.warning("Failed to fetch existing lesson assignments: \(error)")
            existingAssignments = []
        }

        if existingAssignments.contains(where: { Set($0.resolvedStudentIDs) == studentIDs }) {
            lessonToSchedule = nil
            return
        }

        guard lesson.id != nil else {
            lessonToSchedule = nil
            return
        }
        _ = PresentationFactory.makeDraft(
            lesson: lesson,
            students: students,
            context: viewContext
        )
        saveCoordinator.save(viewContext, reason: "Plan presentation")

        lessonToSchedule = nil
    }
}
