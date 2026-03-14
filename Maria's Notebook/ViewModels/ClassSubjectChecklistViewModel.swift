// ClassSubjectChecklistViewModel.swift
// Maria's Notebook
//
// Extracted from ClassSubjectChecklistView.swift for better separation of concerns.
//
// Extensions:
// - ClassSubjectChecklistViewModel+NameDisplay.swift         (displayName, duplicateFirstNameKeys)
// - ClassSubjectChecklistViewModel+CellActions.swift         (toggle/mark/clear individual cells)
// - ClassSubjectChecklistViewModel+PresentationHelpers.swift (findOrCreateWork, upsert/deleteLessonPresentation)

import SwiftUI
import SwiftData
import OSLog

// MARK: - ViewModel
// Manages data loading, subject selection, and matrix state.
// Delegates to:
// - ChecklistMatrixBuilder: Matrix state computation
// - ChecklistBatchActionExecutor: Batch operations
// - ChecklistDragSelectionManager: Drag selection (used in view)
@Observable
@MainActor
class ClassSubjectChecklistViewModel {
    static let logger = Logger.lessons

    var students: [Student] = []
    private var allStudents: [Student] = []
    var lessons: [Lesson] = []
    var orderedGroups: [String] = []
    var availableSubjects: [String] = []
    var selectedSubject: String = ""

    var matrixStates: [UUID: [UUID: StudentChecklistRowState]] = [:]

    // MARK: - Multi-Selection State
    var selectedCells: Set<CellIdentifier> = []
    var isSelectionMode: Bool { !selectedCells.isEmpty }
    private let lessonsLogic = LessonsViewModel()

    // OPTIMIZATION: Cache duplicate name computation to avoid recalculating on every render
    // Internal (not private) so +NameDisplay extension can mutate these cached values.
    var cachedDuplicateFirstNameKeys: Set<String> = []
    var lastStudentHashForDuplicates: Int?

    // OPTIMIZATION: Cache lessons-per-group to avoid filtering + sorting on every body evaluation
    private var cachedLessonsByGroup: [String: [Lesson]] = [:]

    func loadData(context: ModelContext) {
        let studentFetch = FetchDescriptor<Student>(sortBy: [SortDescriptor(\.birthday)])
        let fetched = context.safeFetch(studentFetch)
        self.allStudents = fetched
        self.students = fetched

        let allLessonsFetch = FetchDescriptor<Lesson>()
        let allLessons = context.safeFetch(allLessonsFetch)
        self.availableSubjects = lessonsLogic.subjects(from: allLessons)

        // Consume deep-link filter from AppRouter if present
        let router = AppRouter.shared
        if let filterSubject = router.checklistFilterSubject {
            selectedSubject = filterSubject
            router.checklistFilterSubject = nil
            router.checklistFilterGroup = nil
        } else if selectedSubject.isEmpty, let first = availableSubjects.first {
            selectedSubject = first
        }
        // Refresh lessons and groups but skip matrix recompute —
        // the caller (onAppear) will call applyVisibilityFilter which recomputes.
        refreshLessonsAndGroups(context: context)
    }

    func applyVisibilityFilter(context: ModelContext, show: Bool, namesRaw: String) {
        self.students = TestStudentsFilter.filterVisible(allStudents, show: show, namesRaw: namesRaw)
        recomputeMatrix(context: context)
    }

    /// Refresh lesson list and group ordering without recomputing the matrix.
    private func refreshLessonsAndGroups(context: ModelContext) {
        guard !selectedSubject.isEmpty else { return }
        let sub = selectedSubject.trimmed()
        let lessonsDescriptor = FetchDescriptor<Lesson>()
        let allLessons = context.safeFetch(lessonsDescriptor)
        self.lessons = allLessons.filter { $0.subject.localizedCaseInsensitiveCompare(sub) == .orderedSame }
        self.orderedGroups = lessonsLogic.groups(for: sub, lessons: self.lessons)
        invalidateLessonsCache()
    }

    func refreshMatrix(context: ModelContext) {
        refreshLessonsAndGroups(context: context)
        recomputeMatrix(context: context)
    }

    func lessonsIn(group: String) -> [Lesson] {
        if let cached = cachedLessonsByGroup[group] {
            return cached
        }
        let groupTrimmed = group.trimmed()
        let result = lessons.filter {
            $0.group.trimmed().localizedCaseInsensitiveCompare(groupTrimmed) == .orderedSame
        }.sorted { $0.orderInGroup < $1.orderInGroup }
        cachedLessonsByGroup[group] = result
        return result
    }

    private func invalidateLessonsCache() {
        cachedLessonsByGroup.removeAll()
    }

    func state(for student: Student, lesson: Lesson) -> StudentChecklistRowState? {
        return matrixStates[student.id]?[lesson.id]
    }

    // MARK: - Multi-Selection Methods

    /// Returns the shared lesson ID if all selected cells are for the same lesson, otherwise nil.
    var selectedCellsSameLessonID: UUID? {
        guard !selectedCells.isEmpty else { return nil }
        let lessonIDs = Set(selectedCells.map(\.lessonID))
        return lessonIDs.count == 1 ? lessonIDs.first : nil
    }

    /// Returns the student IDs from the current selection.
    var selectedStudentIDs: Set<UUID> {
        Set(selectedCells.map(\.studentID))
    }

    func toggleSelection(student: Student, lesson: Lesson) {
        let id = CellIdentifier(studentID: student.id, lessonID: lesson.id)
        if selectedCells.contains(id) {
            selectedCells.remove(id)
        } else {
            selectedCells.insert(id)
        }
    }

    func clearSelection() {
        selectedCells.removeAll()
    }

    func isSelected(student: Student, lesson: Lesson) -> Bool {
        selectedCells.contains(CellIdentifier(studentID: student.id, lessonID: lesson.id))
    }

    // MARK: - Batch Actions (delegated to ChecklistBatchActionExecutor)

    func batchAddToInbox(context: ModelContext) {
        ChecklistBatchActionExecutor.batchAddToInbox(
            selectedCells: selectedCells,
            students: students,
            lessons: lessons,
            matrixStates: matrixStates,
            context: context
        )
        recomputeMatrix(context: context)
        clearSelection()
    }

    func batchMarkPresented(context: ModelContext) {
        ChecklistBatchActionExecutor.batchMarkPresented(
            selectedCells: selectedCells,
            students: students,
            lessons: lessons,
            matrixStates: matrixStates,
            context: context
        )
        recomputeMatrix(context: context)
        clearSelection()
    }

    func batchMarkPreviouslyPresented(context: ModelContext) {
        ChecklistBatchActionExecutor.batchMarkPreviouslyPresented(
            selectedCells: selectedCells,
            students: students,
            lessons: lessons,
            matrixStates: matrixStates,
            context: context
        )
        recomputeMatrix(context: context)
        clearSelection()
    }

    func batchMarkProficient(context: ModelContext) {
        ChecklistBatchActionExecutor.batchMarkProficient(
            selectedCells: selectedCells,
            students: students,
            lessons: lessons,
            matrixStates: matrixStates,
            context: context
        )
        recomputeMatrix(context: context)
        clearSelection()
    }

    func batchClearStatus(context: ModelContext) {
        ChecklistBatchActionExecutor.batchClearStatus(
            selectedCells: selectedCells,
            students: students,
            lessons: lessons,
            context: context
        )
        recomputeMatrix(context: context)
        clearSelection()
    }

    // MARK: - Matrix Computation (delegated to ChecklistMatrixBuilder)

    func recomputeMatrix(context: ModelContext) {
        guard !lessons.isEmpty else { matrixStates = [:]; return }
        self.matrixStates = ChecklistMatrixBuilder.buildMatrix(
            students: students,
            lessons: lessons,
            context: context
        )
    }
}
