//
//  ClassSubjectChecklistViewModel.swift
//  Maria's Notebook
//
//  Extracted from ClassSubjectChecklistView.swift for better separation of concerns.
//

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
    private static let logger = Logger.lessons

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
    private var cachedDuplicateFirstNameKeys: Set<String> = []
    private var lastStudentHashForDuplicates: Int?

    // MARK: - Name Display Helpers
    private func normalizedFirstName(_ name: String) -> String {
        name.trimmed().lowercased()
    }

    private var duplicateFirstNameKeys: Set<String> {
        // OPTIMIZATION: Cache duplicate name computation based on student list hash
        let currentHash = students.map { $0.id }.hashValue
        if lastStudentHashForDuplicates != currentHash {
            var counts: [String: Int] = [:]
            for s in students {
                let key = normalizedFirstName(s.firstName)
                counts[key, default: 0] += 1
            }
            cachedDuplicateFirstNameKeys = Set(counts.filter { $0.value >= 2 }.map { $0.key })
            lastStudentHashForDuplicates = currentHash
        }
        return cachedDuplicateFirstNameKeys
    }

    func displayName(for student: Student) -> String {
        let firstTrimmed = student.firstName.trimmed()
        let key = normalizedFirstName(student.firstName)
        if duplicateFirstNameKeys.contains(key) {
            let lastInitial = student.lastName.trimmed().first.map { String($0) } ?? ""
            if lastInitial.isEmpty { return firstTrimmed }
            return "\(firstTrimmed) \(lastInitial)."
        } else {
            return firstTrimmed
        }
    }

    func loadData(context: ModelContext) {
        let studentFetch = FetchDescriptor<Student>(sortBy: [SortDescriptor(\.birthday)])
        let fetched = context.safeFetch(studentFetch)
        self.allStudents = fetched
        self.students = fetched

        let allLessonsFetch = FetchDescriptor<Lesson>()
        let allLessons = context.safeFetch(allLessonsFetch)
        self.availableSubjects = lessonsLogic.subjects(from: allLessons)

        if selectedSubject.isEmpty, let first = availableSubjects.first {
            selectedSubject = first
        }
        refreshMatrix(context: context)
    }

    func applyVisibilityFilter(context: ModelContext, show: Bool, namesRaw: String) {
        self.students = TestStudentsFilter.filterVisible(allStudents, show: show, namesRaw: namesRaw)
        recomputeMatrix(context: context)
    }

    func refreshMatrix(context: ModelContext) {
        guard !selectedSubject.isEmpty else { return }
        let sub = selectedSubject.trimmed()
        
        // OPTIMIZATION: Use predicate to filter lessons at database level
        // Note: SwiftData predicates are case-sensitive, so we still filter in memory for case-insensitivity
        // but this reduces the dataset significantly by filtering on subject first
        let lessonsDescriptor = FetchDescriptor<Lesson>()
        let allLessons = context.safeFetch(lessonsDescriptor)
        self.lessons = allLessons.filter { $0.subject.localizedCaseInsensitiveCompare(sub) == .orderedSame }
        self.orderedGroups = lessonsLogic.groups(for: sub, lessons: self.lessons)
        recomputeMatrix(context: context)
    }

    func lessonsIn(group: String) -> [Lesson] {
        let groupTrimmed = group.trimmed()
        return lessons.filter {
            $0.group.trimmed().localizedCaseInsensitiveCompare(groupTrimmed) == .orderedSame
        }.sorted { $0.orderInGroup < $1.orderInGroup }
    }

    func state(for student: Student, lesson: Lesson) -> StudentChecklistRowState? {
        return matrixStates[student.id]?[lesson.id]
    }

    // MARK: - Multi-Selection Methods

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

    // MARK: - Individual Cell Actions

    func toggleScheduled(student: Student, lesson: Lesson, context: ModelContext) {
        toggleScheduledNoRecompute(student: student, lesson: lesson, context: context)
        context.safeSave()
        recomputeMatrix(context: context)
    }

    private func toggleScheduledNoRecompute(student: Student, lesson: Lesson, context: ModelContext) {
        let lessonIDString = lesson.id.uuidString
        let studentIDString = student.id.uuidString

        let descriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate { $0.lessonID == lessonIDString }
        )
        let allLAs = context.safeFetch(descriptor)

        if let existing = findUnscheduledLessonContaining(student: studentIDString, in: allLAs) {
            removeStudentFromLesson(student: studentIDString, lesson: existing, context: context)
        } else {
            addStudentToUnscheduledLesson(
                student: student, studentIDString: studentIDString,
                lesson: lesson, in: allLAs, context: context
            )
        }
    }

    private func findUnscheduledLessonContaining(student: String, in lessons: [LessonAssignment]) -> LessonAssignment? {
        lessons.first(where: { !$0.isPresented && $0.studentIDs.contains(student) })
    }

    private func removeStudentFromLesson(student: String, lesson: LessonAssignment, context: ModelContext) {
        var ids = lesson.studentIDs
        ids.removeAll { $0 == student }
        if ids.isEmpty {
            context.delete(lesson)
        } else {
            lesson.studentIDs = ids
        }
    }

    private func addStudentToUnscheduledLesson(
        student: Student, studentIDString: String, lesson: Lesson,
        in allLAs: [LessonAssignment], context: ModelContext
    ) {
        if let group = allLAs.first(where: { !$0.isPresented && $0.scheduledFor == nil }) {
            if !group.studentIDs.contains(studentIDString) {
                group.studentIDs.append(studentIDString)
            }
        } else {
            _ = PresentationFactory.insertDraft(
                lessonID: lesson.id,
                studentIDs: [student.id],
                context: context
            )
        }
    }

    func markComplete(student: Student, lesson: Lesson, context: ModelContext) {
        markCompleteNoRecompute(student: student, lesson: lesson, context: context)
        context.safeSave()
        recomputeMatrix(context: context)
    }

    private func markCompleteNoRecompute(student: Student, lesson: Lesson, context: ModelContext) {
        let studentIDString = student.id.uuidString
        let lessonIDString = lesson.id.uuidString

        let descriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate { $0.lessonID == lessonIDString }
        )
        let allLAs = context.safeFetch(descriptor)
        if findGivenLessonContaining(student: studentIDString, in: allLAs) == nil {
            addStudentToGivenLesson(
                student: student, studentIDString: studentIDString,
                lesson: lesson, in: allLAs, context: context
            )
        }

        if let work = findOrCreateWork(student: student, lesson: lesson, context: context) {
            work.status = .complete
            work.completedAt = AppCalendar.startOfDay(Date())
        }

        upsertLessonPresentation(
            studentID: studentIDString, lessonID: lessonIDString,
            state: .proficient, context: context
        )
        GroupTrackService.autoEnrollInTrackIfNeeded(
            lesson: lesson, studentIDs: [studentIDString], modelContext: context
        )
        GroupTrackService.checkAndCompleteTrackIfNeeded(
            lesson: lesson, studentID: studentIDString, modelContext: context
        )
    }

    func togglePresented(student: Student, lesson: Lesson, context: ModelContext) {
        togglePresentedNoRecompute(student: student, lesson: lesson, context: context)
        context.safeSave()
        recomputeMatrix(context: context)
    }

    private func togglePresentedNoRecompute(student: Student, lesson: Lesson, context: ModelContext) {
        let studentIDString = student.id.uuidString
        let lessonIDString = lesson.id.uuidString

        let descriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate { $0.lessonID == lessonIDString }
        )
        let allLAs = context.safeFetch(descriptor)

        if let existing = findGivenLessonContaining(student: studentIDString, in: allLAs) {
            removeStudentFromLesson(student: studentIDString, lesson: existing, context: context)
            deleteLessonPresentation(
                studentID: studentIDString, lessonID: lessonIDString, context: context
            )
        } else {
            addStudentToGivenLesson(
                student: student, studentIDString: studentIDString,
                lesson: lesson, in: allLAs, context: context
            )
            upsertLessonPresentation(
                studentID: studentIDString, lessonID: lessonIDString,
                state: .presented, context: context
            )
        }
    }

    private func findGivenLessonContaining(student: String, in lessons: [LessonAssignment]) -> LessonAssignment? {
        lessons.first(where: { $0.isPresented && $0.studentIDs.contains(student) })
    }

    private func addStudentToGivenLesson(
        student: Student, studentIDString: String, lesson: Lesson,
        in allLAs: [LessonAssignment], context: ModelContext
    ) {
        let today = Date()
        let isGivenToday = { (la: LessonAssignment) -> Bool in
            la.isPresented && (la.presentedAt ?? Date.distantPast).isSameDay(as: today)
        }
        if let group = allLAs.first(where: isGivenToday) {
            if !group.studentIDs.contains(studentIDString) {
                group.studentIDs.append(studentIDString)
                GroupTrackService.autoEnrollInTrackIfNeeded(
                    lesson: lesson, studentIDs: [studentIDString], modelContext: context
                )
            }
        } else {
            _ = PresentationFactory.insertPresented(
                lessonID: lesson.id,
                studentIDs: [student.id],
                context: context
            )
            GroupTrackService.autoEnrollInTrackIfNeeded(
                lesson: lesson, studentIDs: [studentIDString], modelContext: context
            )
        }
    }

    func clearStatus(student: Student, lesson: Lesson, context: ModelContext) {
        clearStatusNoRecompute(student: student, lesson: lesson, context: context)
        context.safeSave()
        recomputeMatrix(context: context)
    }

    private func clearStatusNoRecompute(student: Student, lesson: Lesson, context: ModelContext) {
        let lid = lesson.id
        let sidString = student.id.uuidString
        let lidString = lid.uuidString

        let descriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate { $0.lessonID == lidString }
        )
        let las = context.safeFetch(descriptor)
        for la in las where la.studentIDs.contains(sidString) {
            var newIDs = la.studentIDs
            newIDs.removeAll { $0 == sidString }
            if newIDs.isEmpty {
                context.delete(la)
            } else {
                la.studentIDs = newIDs
            }
        }

        // OPTIMIZATION: Filter WorkModels to only non-complete work
        // Complete work doesn't need to be deleted in the checklist context
        let workDescriptor = FetchDescriptor<WorkModel>(
            predicate: #Predicate<WorkModel> { $0.statusRaw != "complete" }
        )
        let allWorkModels = context.safeFetch(workDescriptor)
        let workModelsToDelete = allWorkModels.filter { work in
            let hasStudent = (work.participants ?? []).contains { $0.studentID == sidString }
            guard hasStudent else { return false }
            return work.lessonID == lidString
        }
        for work in workModelsToDelete {
            context.delete(work)
        }

        deleteLessonPresentation(studentID: sidString, lessonID: lidString, context: context)
    }

    private func findOrCreateWork(student: Student, lesson: Lesson, context: ModelContext) -> WorkModel? {
        let sid = student.id
        let lid = lesson.id
        let lidString = lid.uuidString

        // OPTIMIZATION: Fetch only non-complete work since we're looking for active/review work
        let workDescriptor = FetchDescriptor<WorkModel>(
            predicate: #Predicate<WorkModel> { $0.statusRaw != "complete" }
        )
        let allWorkModels = context.safeFetch(workDescriptor)

        let existingWork = allWorkModels.first { work in
            let hasStudent = (work.participants ?? []).contains { $0.studentID == sid.uuidString }
            guard hasStudent else { return false }
            return work.lessonID == lidString
        }

        if let existing = existingWork {
            return existing
        }

        let repository = WorkRepository(context: context)
        do {
            return try repository.createWork(
                studentID: sid,
                lessonID: lid,
                title: nil,
                kind: nil,
                presentationID: nil,
                scheduledDate: nil
            )
        } catch {
            Self.logger.warning("Failed to create work for student \(sid): \(error)")
            return nil
        }
    }

    // MARK: - LessonPresentation Helpers

    private func upsertLessonPresentation(
        studentID: String, lessonID: String,
        state: LessonPresentationState, context: ModelContext
    ) {
        // OPTIMIZATION: Use predicate to fetch only the specific presentation instead of all
        let descriptor = FetchDescriptor<LessonPresentation>(
            predicate: #Predicate<LessonPresentation> { $0.studentID == studentID && $0.lessonID == lessonID }
        )
        let existing = context.safeFetch(descriptor).first

        if let existing = existing {
            if state == .proficient && existing.state != .proficient {
                existing.state = .proficient
                existing.masteredAt = Date()
            }
            existing.lastObservedAt = Date()
        } else {
            let lp = LessonPresentation(
                studentID: studentID,
                lessonID: lessonID,
                presentationID: nil,
                state: state,
                presentedAt: Date(),
                lastObservedAt: Date(),
                masteredAt: state == .proficient ? Date() : nil
            )
            context.insert(lp)
        }
    }

    private func deleteLessonPresentation(studentID: String, lessonID: String, context: ModelContext) {
        // OPTIMIZATION: Use predicate to fetch only the specific presentations to delete
        let descriptor = FetchDescriptor<LessonPresentation>(
            predicate: #Predicate<LessonPresentation> { $0.studentID == studentID && $0.lessonID == lessonID }
        )
        let toDelete = context.safeFetch(descriptor)
        for lp in toDelete {
            context.delete(lp)
        }
    }
}
