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
import CoreData
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

    var students: [CDStudent] = []
    private var allStudents: [CDStudent] = []
    var lessons: [CDLesson] = []
    var orderedGroups: [String] = []
    var availableSubjects: [String] = []
    var selectedSubject: String = ""

    var matrixStates: [UUID: [UUID: StudentChecklistRowState]] = [:]

    // MARK: - Multi-Selection State
    var selectedCells: Set<CellIdentifier> = []
    var isEditModeActive: Bool = false
    var isSelectionMode: Bool { isEditModeActive || !selectedCells.isEmpty }
    private let lessonsLogic = LessonsViewModel()

    // OPTIMIZATION: Cache duplicate name computation to avoid recalculating on every render
    // Internal (not private) so +NameDisplay extension can mutate these cached values.
    var cachedDuplicateFirstNameKeys: Set<String> = []
    var lastStudentHashForDuplicates: Int?

    // OPTIMIZATION: Cache lessons-per-group to avoid filtering + sorting on every body evaluation
    private var cachedLessonsByGroup: [String: LessonsBySubheading] = [:]

    /// Lessons inside a single group, bucketed by subheading and ordered for display.
    /// `order` lists subheading names in render order ("" appended last when present).
    /// Each `bySubheading` array is pre-sorted by `orderInGroup`, then name.
    /// `hasSubheadings` is `false` when only the empty bucket exists — callers can skip rendering sub-header rows.
    struct LessonsBySubheading {
        let order: [String]
        let bySubheading: [String: [CDLesson]]
        let hasSubheadings: Bool
    }

    func loadData(context: NSManagedObjectContext) {
        let studentFetch = CDFetchRequest(CDStudent.self)
        studentFetch.predicate = CDStudent.enrolledPredicate
        studentFetch.sortDescriptors = [NSSortDescriptor(keyPath: \CDStudent.birthday, ascending: true)]
        let fetched = context.safeFetch(studentFetch)
        self.allStudents = fetched
        self.students = fetched

        let allLessonsFetch = CDFetchRequest(CDLesson.self)
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

    func applyVisibilityFilter(context: NSManagedObjectContext, show: Bool, namesRaw: String) {
        self.students = TestStudentsFilter.filterVisible(allStudents, show: show, namesRaw: namesRaw)
        recomputeMatrix(context: context)
    }

    /// Refresh lesson list and group ordering without recomputing the matrix.
    /// PERF: Uses subject predicate to narrow the query instead of loading all lessons.
    private func refreshLessonsAndGroups(context: NSManagedObjectContext) {
        guard !selectedSubject.isEmpty else { return }
        let sub = selectedSubject.trimmed()
        // Use case-insensitive CONTAINS for subject matching
        let lessonsDescriptor = CDFetchRequest(CDLesson.self)
        lessonsDescriptor.predicate = NSPredicate(format: "subject CONTAINS[cd] %@", sub)
        let fetchedLessons = context.safeFetch(lessonsDescriptor)
        // Post-filter for exact match (localizedStandardContains is substring-based)
        self.lessons = fetchedLessons.filter {
            $0.subject.localizedCaseInsensitiveCompare(sub) == .orderedSame
        }
        self.orderedGroups = lessonsLogic.groups(for: sub, lessons: self.lessons)
        invalidateLessonsCache()
    }

    func refreshMatrix(context: NSManagedObjectContext) {
        refreshLessonsAndGroups(context: context)
        recomputeMatrix(context: context)
    }

    func lessonsGrouped(group: String) -> LessonsBySubheading {
        if let cached = cachedLessonsByGroup[group] {
            return cached
        }
        let groupTrimmed = group.trimmed()
        let groupLessons = lessons.filter {
            $0.group.trimmed().localizedCaseInsensitiveCompare(groupTrimmed) == .orderedSame
        }
        let bySubheadingRaw = Dictionary(grouping: groupLessons) { $0.subheading.trimmed() }
        let bySubheading = bySubheadingRaw.mapValues { lessonsInBucket -> [CDLesson] in
            lessonsInBucket.sorted { lhs, rhs in
                if lhs.orderInGroup != rhs.orderInGroup { return lhs.orderInGroup < rhs.orderInGroup }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }

        let existingNonEmpty = Array(Set(bySubheading.keys.filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let subjectTrimmed = selectedSubject.trimmed()
        let nonEmptyOrder: [String]
        if subjectTrimmed.isEmpty || existingNonEmpty.isEmpty {
            nonEmptyOrder = existingNonEmpty
        } else {
            nonEmptyOrder = FilterOrderStore.loadSubheadingOrder(
                for: subjectTrimmed, group: groupTrimmed, existing: existingNonEmpty
            )
        }

        var order = nonEmptyOrder
        if bySubheading.keys.contains("") {
            order.append("")
        }

        let result = LessonsBySubheading(
            order: order,
            bySubheading: bySubheading,
            hasSubheadings: !existingNonEmpty.isEmpty
        )
        cachedLessonsByGroup[group] = result
        return result
    }

    private func invalidateLessonsCache() {
        cachedLessonsByGroup.removeAll()
    }

    func state(for student: CDStudent, lesson: CDLesson) -> StudentChecklistRowState? {
        guard let sid = student.id, let lid = lesson.id else { return nil }
        return matrixStates[sid]?[lid]
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

    func toggleSelection(student: CDStudent, lesson: CDLesson) {
        guard let sid = student.id, let lid = lesson.id else { return }
        let id = CellIdentifier(studentID: sid, lessonID: lid)
        if selectedCells.contains(id) {
            selectedCells.remove(id)
        } else {
            selectedCells.insert(id)
        }
    }

    func clearSelection() {
        selectedCells.removeAll()
        isEditModeActive = false
    }

    func isSelected(student: CDStudent, lesson: CDLesson) -> Bool {
        guard let sid = student.id, let lid = lesson.id else { return false }
        return selectedCells.contains(CellIdentifier(studentID: sid, lessonID: lid))
    }

    // MARK: - Batch Actions (delegated to ChecklistBatchActionExecutor)

    func batchAddToInbox(context: NSManagedObjectContext) {
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

    func batchMarkPresented(context: NSManagedObjectContext) {
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

    func batchMarkPreviouslyPresented(context: NSManagedObjectContext) {
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

    func batchMarkProficient(context: NSManagedObjectContext) {
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

    func batchClearStatus(context: NSManagedObjectContext) {
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

    func recomputeMatrix(context: NSManagedObjectContext) {
        guard !lessons.isEmpty else { matrixStates = [:]; return }
        self.matrixStates = ChecklistMatrixBuilder.buildMatrix(
            students: students,
            lessons: lessons,
            context: context
        )
    }
}
