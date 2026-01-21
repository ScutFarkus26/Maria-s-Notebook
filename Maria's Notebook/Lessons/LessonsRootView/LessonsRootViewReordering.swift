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
        let allGroups = hasUngrouped ? (baseGroups + [ungroupedLabel]) : baseGroups

        if let subject = selectedSubject, !subject.trimmed().isEmpty {
            let orderedGroups = FilterOrderStore.loadGroupOrder(for: subject, existing: baseGroups)
            let orderedWithUngrouped = hasUngrouped ? (orderedGroups + [ungroupedLabel]) : orderedGroups
            reorderableGroups = orderedWithUngrouped
        } else {
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

        let ungroupedLabel = "Ungrouped"
        let groupsToSave = reordered.filter { $0 != ungroupedLabel }
        FilterOrderStore.saveGroupOrder(groupsToSave, for: subject)
        FilterOrderStore.resetCache()
    }

    // MARK: - Move Lessons in Subject

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

        let ungroupedLabel = "Ungrouped"
        let baseGroups = groupsForSelectedSubject
        let hasUngrouped = lessonsForSubject.contains { $0.group.trimmed().isEmpty }
        let displayGroups = hasUngrouped ? (baseGroups + [ungroupedLabel]) : baseGroups

        var allLessonsInOrder: [Lesson] = []
        for group in displayGroups {
            let groupLessons = lessonsForSubject.filter { lesson in
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
            allLessonsInOrder.append(contentsOf: groupLessons)
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
