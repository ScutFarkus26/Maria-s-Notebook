// LessonsRootViewReordering.swift
// Reordering logic for LessonsRootView - extracted for maintainability

import SwiftUI
import SwiftData
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
    private func moveLessonsFlat(from source: IndexSet, to destination: Int, in allLessons: [Lesson]) {
        guard canReorderInPlanMode else { return }
        guard let sourceIndex = source.first else { return }
        guard sourceIndex < allLessons.count else { return }

        var reordered = allLessons
        reordered.move(fromOffsets: source, toOffset: destination)

        // Update sortIndex for all lessons based on their new position
        for (idx, lesson) in reordered.enumerated() {
            lesson.sortIndex = idx
        }

        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save lesson reorder: \(error)")
        }
    }

    // MARK: - Move Lessons in Subject (legacy, for group-based reordering)

    @MainActor
    func moveLessonsInSubject(from source: IndexSet, to destination: Int, in groupLessons: [Lesson]) {
        guard canReorderInPlanMode else { return }
        guard let subject = selectedSubject, !subject.trimmed().isEmpty else { return }
        guard let sourceIndex = source.first else { return }
        guard sourceIndex < groupLessons.count else { return }

        var reorderedGroup = groupLessons
        reorderedGroup.move(fromOffsets: source, toOffset: destination)

        for (idx, lesson) in reorderedGroup.enumerated() {
            lesson.orderInGroup = idx
        }

        // Use the persisted group order (which includes "Ungrouped" position)
        let ungroupedLabel = "Ungrouped"
        let displayGroups = reorderableGroups

        var allLessonsInOrder: [Lesson] = []
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
            lesson.sortIndex = idx
        }

        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save lesson reorder: \(error)")
        }
    }

    // MARK: - Move Single Lesson Up/Down in Group

    @MainActor
    func moveLessonInGroup(lesson: Lesson, direction: Int, group: String, ungroupedLabel: String) {
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

        var allLessonsInOrder: [Lesson] = []
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
            lesson.sortIndex = idx
        }

        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save lesson reorder: \(error)")
        }
    }

    // MARK: - Move Lesson to Different Group

    @MainActor
    func moveLessonToGroup(lesson: Lesson, newGroup: String) {
        let ungroupedLabel = "Ungrouped"
        let actualGroup = (newGroup == ungroupedLabel) ? "" : newGroup

        lesson.group = actualGroup

        // Set orderInGroup to end of target group
        let targetLessons = lessonsForGroup(newGroup, ungroupedLabel: ungroupedLabel)
        let maxOrder = targetLessons.map(\.orderInGroup).max() ?? -1
        lesson.orderInGroup = maxOrder + 1

        rebuildSortIndexForSubject()
    }

    // MARK: - Move Lesson to Different Subheading

    @MainActor
    func moveLessonToSubheading(lesson: Lesson, newSubheading: String) {
        lesson.subheading = newSubheading

        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save lesson subheading change: \(error)")
        }
    }

    // MARK: - Plan Presentation

    func planPresentation(for lesson: Lesson, studentIDs: Set<UUID>) {
        guard !studentIDs.isEmpty else { return }

        // NOTE: SwiftData #Predicate doesn't support capturing local Array/Set variables,
        // so we fetch all and filter in memory
        let allStudents: [Student]
        do {
            allStudents = try modelContext.fetch(FetchDescriptor<Student>())
        } catch {
            logger.warning("Failed to fetch students: \(error)")
            allStudents = []
        }
        let students = allStudents.filter { studentIDs.contains($0.id) }

        let lessonIDString = lesson.id.uuidString
        let draftRaw = LessonAssignmentState.draft.rawValue
        let existingPredicate = #Predicate<LessonAssignment> { la in
            la.lessonID == lessonIDString &&
            la.stateRaw == draftRaw
        }
        let existingDescriptor = FetchDescriptor<LessonAssignment>(predicate: existingPredicate)
        let existingAssignments: [LessonAssignment]
        do {
            existingAssignments = try modelContext.fetch(existingDescriptor)
        } catch {
            logger.warning("Failed to fetch existing lesson assignments: \(error)")
            existingAssignments = []
        }

        if existingAssignments.contains(where: { Set($0.resolvedStudentIDs) == studentIDs }) {
            lessonToSchedule = nil
            return
        }

        let newAssignment = PresentationFactory.makeDraft(
            lessonID: lesson.id,
            studentIDs: Array(studentIDs)
        )
        PresentationFactory.attachRelationships(
            to: newAssignment,
            lesson: lesson,
            students: students
        )
        modelContext.insert(newAssignment)
        _ = saveCoordinator.save(modelContext, reason: "Plan presentation")

        lessonToSchedule = nil
    }
}
