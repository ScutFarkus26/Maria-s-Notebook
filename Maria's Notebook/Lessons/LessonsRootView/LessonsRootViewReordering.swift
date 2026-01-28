// LessonsRootViewReordering.swift
// Reordering logic for LessonsRootView - extracted for maintainability

import SwiftUI
import SwiftData

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

    // MARK: - Move Lessons Flat (for ungrouped individual positioning)

    @MainActor
    func moveLessonsFlat(from source: IndexSet, to destination: Int, in allLessons: [Lesson]) {
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
            #if DEBUG
            print("Failed to save lesson reorder: \(error)")
            #endif
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
            #if DEBUG
            print("Failed to save lesson reorder: \(error)")
            #endif
        }
    }

    // MARK: - Plan Presentation

    func planPresentation(for lesson: Lesson, studentIDs: Set<UUID>) {
        guard !studentIDs.isEmpty else { return }

        // NOTE: SwiftData #Predicate doesn't support capturing local Array/Set variables,
        // so we fetch all and filter in memory
        let allStudents = (try? modelContext.fetch(FetchDescriptor<Student>())) ?? []
        let students = allStudents.filter { studentIDs.contains($0.id) }

        let lessonIDString = lesson.id.uuidString
        let existingPredicate = #Predicate<StudentLesson> { sl in
            sl.lessonID == lessonIDString &&
            sl.scheduledFor == nil &&
            sl.givenAt == nil
        }
        let existingDescriptor = FetchDescriptor<StudentLesson>(predicate: existingPredicate)
        let existingLessons = (try? modelContext.fetch(existingDescriptor)) ?? []

        if existingLessons.contains(where: { Set($0.resolvedStudentIDs) == studentIDs }) {
            lessonToSchedule = nil
            return
        }

        let newStudentLesson = StudentLessonFactory.makeUnscheduled(
            lessonID: lesson.id,
            studentIDs: Array(studentIDs)
        )
        StudentLessonFactory.attachRelationships(
            to: newStudentLesson,
            lesson: lesson,
            students: students
        )
        modelContext.insert(newStudentLesson)
        _ = saveCoordinator.save(modelContext, reason: "Plan presentation")

        lessonToSchedule = nil
    }
}
