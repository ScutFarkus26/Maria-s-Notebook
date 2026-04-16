// LessonsRootViewReordering.swift
// Reordering logic for LessonsRootView - extracted for maintainability

import SwiftUI
import CoreData
import OSLog

private let logger = Logger.lessons

// MARK: - LessonsRootView Reordering Extension

extension LessonsRootView {

    // MARK: - Sync Reorderable Groups

    func syncReorderableGroups() {
        let ungroupedLabel = "Ungrouped"
        let baseGroups = groupsForSelectedSubject
        let hasUngrouped = lessonsForSubject.contains { $0.group.trimmed().isEmpty }

        if let subject = selectedSubject, !subject.trimmed().isEmpty {
            // Include "Ungrouped" in existing groups so its position is preserved by mergeOrder
            let existingWithUngrouped = hasUngrouped ? (baseGroups + [ungroupedLabel]) : baseGroups
            let orderedGroups = FilterOrderStore.loadGroupOrder(for: subject, existing: existingWithUngrouped)
            reorderableGroups = orderedGroups
        } else {
            let allGroups = hasUngrouped ? (baseGroups + [ungroupedLabel]) : baseGroups
            reorderableGroups = allGroups
        }
    }

    // MARK: - Move Groups

    @MainActor
    func moveGroups(from source: IndexSet, to destination: Int, in groups: [String]) {
        guard let subject = selectedSubject, !subject.trimmed().isEmpty else { return }
        guard let sourceIndex = source.first else { return }
        guard sourceIndex < groups.count else { return }

        var reordered = groups
        reordered.move(fromOffsets: source, toOffset: destination)

        reorderableGroups = reordered

        // Save the full order including "Ungrouped" so its position is preserved
        FilterOrderStore.saveGroupOrder(reordered, for: subject)
        FilterOrderStore.resetCache()
    }

    // MARK: - Move Group Up/Down

    @MainActor
    func moveGroupUpDown(group: String, direction: Int, in groups: [String]) {
        guard let subject = selectedSubject, !subject.trimmed().isEmpty else { return }
        guard let index = groups.firstIndex(of: group) else { return }

        let target = index + direction
        guard target >= 0, target < groups.count else { return }

        var reordered = groups
        reordered.swapAt(index, target)

        reorderableGroups = reordered
        FilterOrderStore.saveGroupOrder(reordered, for: subject)
        FilterOrderStore.resetCache()
    }

    // MARK: - Move Lessons Flat (for ungrouped individual positioning)

    @MainActor
    private func moveLessonsFlat(from source: IndexSet, to destination: Int, in allLessons: [CDLesson]) {
        guard canReorderInPlanMode else { return }
        guard let sourceIndex = source.first else { return }
        guard sourceIndex < allLessons.count else { return }

        var reordered = allLessons
        reordered.move(fromOffsets: source, toOffset: destination)

        // Update sortIndex for all lessons based on their new position
        for (idx, lesson) in reordered.enumerated() {
            lesson.sortIndex = Int64(idx)
        }

        do {
            try viewContext.save()
        } catch {
            logger.error("Failed to save lesson reorder: \(error)")
        }
    }

    // MARK: - Move Lessons in Subject (legacy, for group-based reordering)

    @MainActor
    func moveLessonsInSubject(from source: IndexSet, to destination: Int, in groupLessons: [CDLesson]) {
        // Allow reordering in both browse (jiggle) and plan modes.
        guard canReorder else { return }
        guard let subject = selectedSubject, !subject.trimmed().isEmpty else { return }
        guard let sourceIndex = source.first else { return }
        guard sourceIndex < groupLessons.count else { return }

        var reorderedGroup: [CDLesson] = groupLessons
        reorderedGroup.move(fromOffsets: source, toOffset: destination)

        for (idx, lesson) in reorderedGroup.enumerated() {
            lesson.orderInGroup = Int64(idx)
        }

        let ungroupedLabel: String = "Ungrouped"
        let displayGroups: [String] = reorderableGroups
        let allLessonsInOrder: [CDLesson] = collectOrderedLessons(
            displayGroups: displayGroups,
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

    private func collectOrderedLessons(displayGroups: [String], ungroupedLabel: String) -> [CDLesson] {
        var result: [CDLesson] = []
        for group in displayGroups {
            let trimmedGroup: String = group.trimmed()
            let lessonsInGroup: [CDLesson] = lessonsForSubject.filter { (lesson: CDLesson) -> Bool in
                let lessonGroupTrimmed: String = lesson.group.trimmed()
                if group == ungroupedLabel {
                    return lessonGroupTrimmed.isEmpty
                } else {
                    return lessonGroupTrimmed.caseInsensitiveCompare(trimmedGroup) == .orderedSame
                }
            }.sorted { (lhs: CDLesson, rhs: CDLesson) -> Bool in
                if lhs.orderInGroup != rhs.orderInGroup {
                    return lhs.orderInGroup < rhs.orderInGroup
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            result.append(contentsOf: lessonsInGroup)
        }
        return result
    }

    // MARK: - Move Single CDLesson Up/Down in Group

    @MainActor
    func moveLessonInGroup(lesson: CDLesson, direction: Int, group: String, ungroupedLabel: String) {
        guard canReorderInPlanMode else { return }

        let groupLessons = lessonsForGroup(group, ungroupedLabel: ungroupedLabel)
        guard let index = groupLessons.firstIndex(where: { $0.id == lesson.id }) else { return }

        let target = index + direction
        guard target >= 0, target < groupLessons.count else { return }

        // Swap orderInGroup between the two lessons
        let neighbor = groupLessons[target]
        let tempOrder = lesson.orderInGroup
        lesson.orderInGroup = neighbor.orderInGroup
        neighbor.orderInGroup = tempOrder

        // Rebuild sortIndex across the entire subject
        rebuildSortIndexForSubject()
    }

    /// Rebuilds `sortIndex` for all lessons in the selected subject based on group order and `orderInGroup`.
    @MainActor
    private func rebuildSortIndexForSubject() {
        let ungroupedLabel = "Ungrouped"
        let displayGroups = reorderableGroups

        var allLessonsInOrder: [CDLesson] = []
        for group in displayGroups {
            let lessonsInGroup = lessonsForSubject.filter { lesson in
                let lessonGroupTrimmed = lesson.group.trimmed()
                if group == ungroupedLabel {
                    return lessonGroupTrimmed.isEmpty
                } else {
                    return lessonGroupTrimmed.caseInsensitiveCompare(group.trimmed()) == .orderedSame
                }
            }.sorted { lhs, rhs in
                if lhs.orderInGroup != rhs.orderInGroup {
                    return lhs.orderInGroup < rhs.orderInGroup
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            allLessonsInOrder.append(contentsOf: lessonsInGroup)
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
    func moveLessonToGroup(lesson: CDLesson, newGroup: String) {
        let ungroupedLabel = "Ungrouped"
        let actualGroup = (newGroup == ungroupedLabel) ? "" : newGroup

        lesson.group = actualGroup

        // Set orderInGroup to end of target group
        let targetLessons = lessonsForGroup(newGroup, ungroupedLabel: ungroupedLabel)
        let maxOrder = targetLessons.map(\.orderInGroup).max() ?? -1
        lesson.orderInGroup = maxOrder + 1

        rebuildSortIndexForSubject()
    }

    // MARK: - Move CDLesson to Different Subheading

    @MainActor
    func moveLessonToSubheading(lesson: CDLesson, newSubheading: String) {
        lesson.subheading = newSubheading

        do {
            try viewContext.save()
        } catch {
            logger.error("Failed to save lesson subheading change: \(error)")
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
        let students = allStudents.filter { guard let sid = $0.id else { return false }; return studentIDs.contains(sid) }

        let lessonIDString = lesson.id?.uuidString ?? ""
        let draftRaw = LessonAssignmentState.draft.rawValue
        let existingPredicate = NSPredicate(format: "lessonID == %@ AND stateRaw == %@", lessonIDString as CVarArg, draftRaw as CVarArg)
        let existingDescriptor = { let r = NSFetchRequest<CDLessonAssignment>(entityName: "LessonAssignment"); r.predicate = existingPredicate; return r }()
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
