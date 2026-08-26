// ClassAreaChecklistViewModel.swift
// Maria's Notebook
//
// Extracted from ClassAreaChecklistView.swift for better separation of concerns.
//
// Extensions:
// - ClassAreaChecklistViewModel+NameDisplay.swift         (displayName, duplicateFirstNameKeys)
// - ClassAreaChecklistViewModel+CellActions.swift         (toggle/mark/clear individual cells)
// - ClassAreaChecklistViewModel+PresentationHelpers.swift (findOrCreateWork, upsert/deleteLessonPresentation)

import SwiftUI
import CoreData
import OSLog

// MARK: - ViewModel
// Manages data loading, area selection, and matrix state.
// Delegates to:
// - ChecklistMatrixBuilder: Matrix state computation
// - ChecklistBatchActionExecutor: Batch operations
// - ChecklistDragSelectionManager: Drag selection (used in view)
@Observable
@MainActor
class ClassAreaChecklistViewModel {
    static let logger = Logger.lessons

    // The derived collections below are written by +Filtering.applyFilters(), which lives in
    // another file — hence internal rather than private(set). Views read them only.

    /// The columns actually drawn: `rosterStudents` narrowed by `studentFilterIDs`.
    var students: [CDStudent] = []
    private var allStudents: [CDStudent] = []
    /// Every student the guide can filter to — the enrolled roster minus hidden test students.
    /// Column labels and the matrix key off this rather than `students`, so neither churns
    /// as the filter opens and closes.
    var rosterStudents: [CDStudent] = []
    /// Every lesson in the selected area.
    var lessons: [CDLesson] = []
    /// The rows actually drawn: `lessons` narrowed by `appliedLessonQuery`.
    var visibleLessons: [CDLesson] = []
    /// Every sequence in the selected area.
    var orderedSequences: [String] = []
    /// Sequences that still hold at least one visible lesson.
    var visibleSequences: [String] = []
    var availableAreas: [String] = []
    var selectedArea: String = ""

    // MARK: - Filter State
    // Both filters are display-only: they hide rows and columns and never touch records.
    // The matrix stays built over the whole area, so toggling a filter costs no fetches.

    /// Live text from the filter field. `appliedLessonQuery` trails it by the field's debounce.
    var lessonQuery: String = ""
    /// The debounced query the visible rows were computed from.
    var appliedLessonQuery: String = ""
    var lessonQueryTokens: [String] = []
    /// Empty means every student is shown.
    var studentFilterIDs: Set<UUID> = []
    /// Areas other than the selected one that hold matches for the current query.
    /// Populated only while the selected area has none, to keep the grid from dead-ending.
    var otherAreaMatches: [ChecklistAreaMatchCount] = []

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

    // OPTIMIZATION: Cache lessons-per-sequence to avoid filtering + sorting on every body evaluation.
    // Internal (not private) so the +Filtering extension can invalidate it when a filter changes.
    var cachedLessonsBySequence: [String: LessonsBySection] = [:]

    /// Lessons inside a single sequence, bucketed by section and ordered for display.
    /// `order` lists section names in render order ("" appended last when present).
    /// Each `bySection` array is pre-sorted by `orderInSequence`, then name.
    /// `hasSections` is `false` when only the empty bucket exists — callers can skip rendering sub-header rows.
    struct LessonsBySection {
        let order: [String]
        let bySection: [String: [CDLesson]]
        let hasSections: Bool
    }

    func loadData(context: NSManagedObjectContext) {
        let studentFetch = CDFetchRequest(CDStudent.self)
        studentFetch.predicate = CDStudent.enrolledPredicate
        studentFetch.sortDescriptors = [NSSortDescriptor(keyPath: \CDStudent.birthday, ascending: true)]
        let fetched = context.safeFetch(studentFetch)
        self.allStudents = fetched
        self.rosterStudents = fetched
        self.students = fetched

        let allLessonsFetch = CDFetchRequest(CDLesson.self)
        let allLessons = context.safeFetch(allLessonsFetch)
        self.availableAreas = lessonsLogic.areas(from: allLessons)

        // Consume deep-link filter from AppRouter if present
        let router = AppRouter.shared
        if let filterArea = router.checklistFilterArea {
            selectedArea = filterArea
            router.checklistFilterArea = nil
            router.checklistFilterSequence = nil
        } else if selectedArea.isEmpty, let first = availableAreas.first {
            selectedArea = first
        }
        // Refresh lessons and groups but skip matrix recompute —
        // the caller (onAppear) will call applyVisibilityFilter which recomputes.
        refreshLessonsAndSequences(context: context)
    }

    func applyVisibilityFilter(context: NSManagedObjectContext, show: Bool, namesRaw: String) {
        self.rosterStudents = TestStudentsFilter.filterVisible(allStudents, show: show, namesRaw: namesRaw)
        applyFilters()
        recomputeMatrix(context: context)
    }

    /// Refresh lesson list and sequence ordering without recomputing the matrix.
    /// PERF: Uses area predicate to narrow the query instead of loading all lessons.
    private func refreshLessonsAndSequences(context: NSManagedObjectContext) {
        guard !selectedArea.isEmpty else { return }
        let sub = selectedArea.trimmed()
        // Use case-insensitive CONTAINS for area matching
        let lessonsDescriptor = CDFetchRequest(CDLesson.self)
        lessonsDescriptor.predicate = NSPredicate(format: "area CONTAINS[cd] %@", sub)
        let fetchedLessons = context.safeFetch(lessonsDescriptor)
        // Post-filter for exact match (localizedStandardContains is substring-based)
        self.lessons = fetchedLessons.filter {
            $0.area.localizedCaseInsensitiveCompare(sub) == .orderedSame
        }
        self.orderedSequences = lessonsLogic.groups(for: sub, lessons: self.lessons)
        applyFilters()
    }

    func refreshMatrix(context: NSManagedObjectContext) {
        refreshLessonsAndSequences(context: context)
        refreshOtherAreaMatches(context: context)
        recomputeMatrix(context: context)
    }

    func lessonsSequenced(sequence: String) -> LessonsBySection {
        if let cached = cachedLessonsBySequence[sequence] {
            return cached
        }
        let groupTrimmed = sequence.trimmed()
        let groupLessons = visibleLessons.filter {
            $0.sequence.trimmed().localizedCaseInsensitiveCompare(groupTrimmed) == .orderedSame
        }
        let bySectionRaw = Dictionary(grouping: groupLessons) { $0.section.trimmed() }
        let bySection = bySectionRaw.mapValues { lessonsInBucket -> [CDLesson] in
            lessonsInBucket.sorted { lhs, rhs in
                if lhs.orderInSequence != rhs.orderInSequence { return lhs.orderInSequence < rhs.orderInSequence }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }

        let existingNonEmpty = Array(Set(bySection.keys.filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let areaTrimmed = selectedArea.trimmed()
        let nonEmptyOrder: [String]
        if areaTrimmed.isEmpty || existingNonEmpty.isEmpty {
            nonEmptyOrder = existingNonEmpty
        } else {
            nonEmptyOrder = FilterOrderStore.loadSectionOrder(
                for: areaTrimmed, sequence: groupTrimmed, existing: existingNonEmpty
            )
        }

        var order = nonEmptyOrder
        if bySection.keys.contains("") {
            order.append("")
        }

        let result = LessonsBySection(
            order: order,
            bySection: bySection,
            hasSections: !existingNonEmpty.isEmpty
        )
        cachedLessonsBySequence[sequence] = result
        return result
    }

    func invalidateLessonsCache() {
        cachedLessonsBySequence.removeAll()
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

    /// Builds over the full roster and the full area rather than the filtered subsets, so
    /// narrowing or widening a filter is a pure re-render with no Core Data work behind it.
    func recomputeMatrix(context: NSManagedObjectContext) {
        guard !lessons.isEmpty else { matrixStates = [:]; return }
        self.matrixStates = ChecklistMatrixBuilder.buildMatrix(
            students: rosterStudents,
            lessons: lessons,
            context: context
        )
    }
}
