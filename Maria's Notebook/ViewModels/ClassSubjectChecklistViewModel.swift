//
//  ClassSubjectChecklistViewModel.swift
//  Maria's Notebook
//
//  Extracted from ClassSubjectChecklistView.swift for better separation of concerns.
//

import SwiftUI
import SwiftData
import Combine

// MARK: - ViewModel
// Manages data loading, subject selection, and matrix state.
// Delegates to:
// - ChecklistMatrixBuilder: Matrix state computation
// - ChecklistBatchActionExecutor: Batch operations
// - ChecklistDragSelectionManager: Drag selection (used in view)
@MainActor
class ClassSubjectChecklistViewModel: ObservableObject {
    @Published var students: [Student] = []
    private var allStudents: [Student] = []
    @Published var lessons: [Lesson] = []
    @Published var orderedGroups: [String] = []
    @Published var availableSubjects: [String] = []
    @Published var selectedSubject: String = ""

    @Published var matrixStates: [UUID: [UUID: StudentChecklistRowState]] = [:]

    // MARK: - Multi-Selection State
    @Published var selectedCells: Set<CellIdentifier> = []
    var isSelectionMode: Bool { !selectedCells.isEmpty }
    private let lessonsLogic = LessonsViewModel()

    // MARK: - Name Display Helpers
    private func normalizedFirstName(_ name: String) -> String {
        name.trimmed().lowercased()
    }

    private var duplicateFirstNameKeys: Set<String> {
        var counts: [String: Int] = [:]
        for s in students {
            let key = normalizedFirstName(s.firstName)
            counts[key, default: 0] += 1
        }
        return Set(counts.filter { $0.value >= 2 }.map { $0.key })
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
        // Filter lessons by subject (case-insensitive to match original behavior)
        let allLessons = context.safeFetch(FetchDescriptor<Lesson>())
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

    func batchMarkMastered(context: ModelContext) {
        ChecklistBatchActionExecutor.batchMarkMastered(
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

        let allSLs = context.safeFetch(FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.lessonID == lessonIDString }))

        if let existing = findUnscheduledLessonContaining(student: studentIDString, in: allSLs) {
            removeStudentFromLesson(student: studentIDString, lesson: existing, context: context)
        } else {
            addStudentToUnscheduledLesson(student: student, studentIDString: studentIDString, lesson: lesson, in: allSLs, context: context)
        }
    }

    private func findUnscheduledLessonContaining(student: String, in lessons: [StudentLesson]) -> StudentLesson? {
        lessons.first(where: { !$0.isGiven && $0.studentIDs.contains(student) })
    }

    private func removeStudentFromLesson(student: String, lesson: StudentLesson, context: ModelContext) {
        var ids = lesson.studentIDs
        ids.removeAll { $0 == student }
        if ids.isEmpty {
            context.delete(lesson)
        } else {
            lesson.studentIDs = ids
        }
    }

    private func addStudentToUnscheduledLesson(student: Student, studentIDString: String, lesson: Lesson, in allSLs: [StudentLesson], context: ModelContext) {
        if let group = allSLs.first(where: { !$0.isGiven && $0.scheduledFor == nil }) {
            if !group.studentIDs.contains(studentIDString) {
                group.studentIDs.append(studentIDString)
            }
        } else {
            _ = StudentLessonFactory.insertUnscheduled(
                lessonID: lesson.id,
                studentIDs: [student.id],
                into: context
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

        let allSLs = context.safeFetch(FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.lessonID == lessonIDString }))
        if findGivenLessonContaining(student: studentIDString, in: allSLs) == nil {
            addStudentToGivenLesson(student: student, studentIDString: studentIDString, lesson: lesson, in: allSLs, context: context)
        }

        if let work = findOrCreateWork(student: student, lesson: lesson, context: context) {
            work.status = .complete
            work.completedAt = AppCalendar.startOfDay(Date())
        }

        upsertLessonPresentation(studentID: studentIDString, lessonID: lessonIDString, state: .mastered, context: context)
        GroupTrackService.autoEnrollInTrackIfNeeded(lesson: lesson, studentIDs: [studentIDString], modelContext: context)
        GroupTrackService.checkAndCompleteTrackIfNeeded(lesson: lesson, studentID: studentIDString, modelContext: context)
    }

    func togglePresented(student: Student, lesson: Lesson, context: ModelContext) {
        togglePresentedNoRecompute(student: student, lesson: lesson, context: context)
        context.safeSave()
        recomputeMatrix(context: context)
    }

    private func togglePresentedNoRecompute(student: Student, lesson: Lesson, context: ModelContext) {
        let studentIDString = student.id.uuidString
        let lessonIDString = lesson.id.uuidString

        let allSLs = context.safeFetch(FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.lessonID == lessonIDString }))

        if let existing = findGivenLessonContaining(student: studentIDString, in: allSLs) {
            removeStudentFromLesson(student: studentIDString, lesson: existing, context: context)
            deleteLessonPresentation(studentID: studentIDString, lessonID: lessonIDString, context: context)
        } else {
            addStudentToGivenLesson(student: student, studentIDString: studentIDString, lesson: lesson, in: allSLs, context: context)
            upsertLessonPresentation(studentID: studentIDString, lessonID: lessonIDString, state: .presented, context: context)
        }
    }

    private func findGivenLessonContaining(student: String, in lessons: [StudentLesson]) -> StudentLesson? {
        lessons.first(where: { $0.isGiven && $0.studentIDs.contains(student) })
    }

    private func addStudentToGivenLesson(student: Student, studentIDString: String, lesson: Lesson, in allSLs: [StudentLesson], context: ModelContext) {
        let today = Date()
        if let group = allSLs.first(where: { $0.isGiven && ($0.givenAt ?? Date.distantPast).isSameDay(as: today) }) {
            if !group.studentIDs.contains(studentIDString) {
                group.studentIDs.append(studentIDString)
                GroupTrackService.autoEnrollInTrackIfNeeded(lesson: lesson, studentIDs: [studentIDString], modelContext: context)
            }
        } else {
            _ = StudentLessonFactory.insertPresented(
                lessonID: lesson.id,
                studentIDs: [student.id],
                into: context
            )
            GroupTrackService.autoEnrollInTrackIfNeeded(lesson: lesson, studentIDs: [studentIDString], modelContext: context)
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

        let sls = context.safeFetch(FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.lessonID == lidString }))
        for sl in sls where sl.studentIDs.contains(sidString) {
            var newIDs = sl.studentIDs
            newIDs.removeAll { $0 == sidString }
            if newIDs.isEmpty { context.delete(sl) } else { sl.studentIDs = newIDs }
        }

        let allWorkModels = context.safeFetch(FetchDescriptor<WorkModel>())
        let workModelsToDelete = allWorkModels.filter { work in
            let hasStudent = (work.participants ?? []).contains { $0.studentID == sidString }
            guard hasStudent else { return false }
            guard let slID = work.studentLessonID,
                  let sl = sls.first(where: { $0.id == slID }),
                  UUID(uuidString: sl.lessonID) == lid else { return false }
            return true
        }
        for work in workModelsToDelete {
            context.delete(work)
        }

        deleteLessonPresentation(studentID: sidString, lessonID: lidString, context: context)
    }

    private func findOrCreateWork(student: Student, lesson: Lesson, context: ModelContext) -> WorkModel? {
        let sid = student.id
        let lid = lesson.id
        let allWorkModels = context.safeFetch(FetchDescriptor<WorkModel>())

        let existingWork = allWorkModels.first { work in
            let hasStudent = (work.participants ?? []).contains { $0.studentID == sid.uuidString }
            guard hasStudent else { return false }
            guard let slID = work.studentLessonID else { return false }
            let allSLs = context.safeFetch(FetchDescriptor<StudentLesson>())
            guard let sl = allSLs.first(where: { $0.id == slID }),
                  UUID(uuidString: sl.lessonID) == lid else { return false }
            return true
        }

        if let existing = existingWork {
            return existing
        }

        let repository = WorkRepository(context: context)
        return try? repository.createWork(
            studentID: sid,
            lessonID: lid,
            title: nil,
            kind: nil,
            presentationID: nil,
            scheduledDate: nil
        )
    }

    // MARK: - LessonPresentation Helpers

    private func upsertLessonPresentation(studentID: String, lessonID: String, state: LessonPresentationState, context: ModelContext) {
        let allLessonPresentations = context.safeFetch(FetchDescriptor<LessonPresentation>())
        let existing = allLessonPresentations.first { lp in
            lp.studentID == studentID && lp.lessonID == lessonID
        }

        if let existing = existing {
            if state == .mastered && existing.state != .mastered {
                existing.state = .mastered
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
                masteredAt: state == .mastered ? Date() : nil
            )
            context.insert(lp)
        }
    }

    private func deleteLessonPresentation(studentID: String, lessonID: String, context: ModelContext) {
        let allLessonPresentations = context.safeFetch(FetchDescriptor<LessonPresentation>())
        let toDelete = allLessonPresentations.filter { lp in
            lp.studentID == studentID && lp.lessonID == lessonID
        }
        for lp in toDelete {
            context.delete(lp)
        }
    }
}
