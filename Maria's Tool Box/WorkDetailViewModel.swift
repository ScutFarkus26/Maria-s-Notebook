import SwiftUI
import SwiftData
import Combine

final class WorkDetailViewModel: ObservableObject {
    @Published var selectedStudentIDs: Set<UUID>
    @Published var workType: WorkModel.WorkType
    @Published var selectedStudentLessonID: UUID?
    @Published var title: String
    @Published var notes: String
    @Published var completedAt: Date?

    @Published var checkIns: [WorkCheckIn]

    // Caches
    @Published private(set) var lessonsByID: [UUID: Lesson] = [:]
    @Published private(set) var studentsByID: [UUID: Student] = [:]
    @Published private(set) var studentLessonsByID: [UUID: StudentLesson] = [:]
    @Published private(set) var studentLessonSnapshotsByID: [UUID: StudentLessonSnapshot] = [:]

    let work: WorkModel
    var onDone: (() -> Void)? = nil

    init(work: WorkModel, onDone: (() -> Void)? = nil) {
        self.work = work
        self.onDone = onDone
        self.selectedStudentIDs = Set(work.participants.map { $0.studentID })
        self.workType = work.workType
        self.selectedStudentLessonID = work.studentLessonID
        self.title = work.title
        self.notes = work.notes
        self.completedAt = work.completedAt
        self.checkIns = work.checkIns
    }

    func rebuildCaches(lessons: [Lesson], students: [Student], studentLessons: [StudentLesson]) {
        lessonsByID = Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })
        studentsByID = Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) })
        studentLessonsByID = Dictionary(uniqueKeysWithValues: studentLessons.map { ($0.id, $0) })
        studentLessonSnapshotsByID = Dictionary(uniqueKeysWithValues: studentLessonsByID.map { ($0.key, $0.value.snapshot()) })
    }

    var selectedStudentsList: [Student] {
        studentsByID.values
            .filter { selectedStudentIDs.contains($0.id) }
            .sorted { $0.firstName.localizedCaseInsensitiveCompare($1.firstName) == .orderedAscending }
    }

    var studentLiteList: [StudentLite] {
        selectedStudentsList.map { s in
            StudentLite(id: s.id, name: displayName(for: s))
        }
    }

    private func displayName(for student: Student) -> String {
        return StudentFormatter.displayName(for: student)
    }

    func isStudentCompletedDraft(_ studentID: UUID) -> Bool {
        work.isStudentCompleted(studentID)
    }

    func setStudentCompletedDraft(_ studentID: UUID, _ completed: Bool) {
        if completed {
            work.markStudent(studentID, completedAt: Date())
        } else {
            work.markStudent(studentID, completedAt: nil)
        }
    }

    func addCheckInDraft(date: Date, purpose: String, note: String, modelContext: ModelContext) {
        let trimmedPurpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let ci = WorkCheckIn(workID: work.id, date: date, status: .scheduled, purpose: trimmedPurpose, note: trimmedNote, work: work)
        checkIns.append(ci)
        work.checkIns.append(ci)
        modelContext.insert(ci)
    }

    func setCheckInDraftStatus(_ id: UUID, to status: WorkCheckInStatus) {
        guard let index = checkIns.firstIndex(where: { $0.id == id }) else { return }
        checkIns[index].status = status
    }
    
    func updateCheckInNote(_ id: UUID, note: String) {
        guard let index = checkIns.firstIndex(where: { $0.id == id }) else { return }
        checkIns[index].note = note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func deleteCheckInDraft(_ ci: WorkCheckIn, modelContext: ModelContext) {
        if let idx = checkIns.firstIndex(where: { $0.id == ci.id }) {
            checkIns.remove(at: idx)
        }
        work.checkIns.removeAll(where: { $0.id == ci.id })
        modelContext.delete(ci)
    }

    var subject: String {
        if let slID = selectedStudentLessonID,
           let snap = studentLessonSnapshotsByID[slID],
           let lesson = lessonsByID[snap.lessonID] {
            return lesson.subject
        }
        return ""
    }

    var subjectColor: Color {
        subject.isEmpty ? .accentColor : AppColors.color(forSubject: subject)
    }

    func save(modelContext: ModelContext, dismiss: @escaping () -> Void) {
        // Enforce: no work should save without a student attached
        if selectedStudentIDs.isEmpty {
            modelContext.delete(work)
            // Persistence handled by caller via SaveCoordinator; do not save here.
            if let onDone = onDone { onDone() } else { dismiss() }
            return
        }

        work.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        work.workType = workType
        work.studentLessonID = selectedStudentLessonID
        work.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        // Rebuild participants from selectedStudentIDs, preserving completion where possible
        let existing = Dictionary(uniqueKeysWithValues: work.participants.map { ($0.studentID, $0.completedAt) })
        work.participants = Array(selectedStudentIDs).map { sid in
            WorkParticipantEntity(studentID: sid, completedAt: existing[sid] ?? nil, work: work)
        }

        // Safety: if participants are still empty, delete this work
        if work.participants.isEmpty {
            modelContext.delete(work)
            // Persistence handled by caller via SaveCoordinator; do not save here.
            if let onDone = onDone { onDone() } else { dismiss() }
            return
        }

        work.completedAt = completedAt
        // Persistence handled by caller via SaveCoordinator; do not save here.
        if let onDone = onDone {
            onDone()
        } else {
            dismiss()
        }
    }

    func deleteWork(modelContext: ModelContext, dismiss: @escaping () -> Void) {
        // Route deletion through the repository for safe, fault-resolved delete
        let repo = WorkRepository(context: modelContext)
        do {
            try repo.deleteWork(id: work.id)
            dismiss()
        } catch {
            // Handle save/delete error if needed
            dismiss()
        }
    }
    
    // Added for phase 3 editing of check-in drafts:
    struct CheckInDraft: Identifiable, Equatable {
        var id: UUID
        var date: Date
        var status: WorkCheckInStatus
        var purpose: String
        var note: String
    }
    
    func updateCheckInDraft(_ draft: CheckInDraft) {
        guard let idx = checkIns.firstIndex(where: { $0.id == draft.id }) else { return }
        checkIns[idx].date = draft.date
        checkIns[idx].status = draft.status
        checkIns[idx].purpose = draft.purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        checkIns[idx].note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var checkInDrafts: [CheckInDraft] {
        checkIns.map { ci in
            CheckInDraft(id: ci.id, date: ci.date, status: ci.status, purpose: ci.purpose, note: ci.note)
        }
    }
}

