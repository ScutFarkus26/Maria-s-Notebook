import SwiftUI
import SwiftData
import Foundation
import Combine

@MainActor
final class WorkDetailVM: ObservableObject {
    let work: WorkModel

    @Published var title: String
    @Published var notes: String
    @Published var workType: WorkModel.WorkType
    @Published var selectedStudentIDs: Set<UUID>
    @Published var selectedStudentLessonID: UUID?
    @Published var completedAt: Date?

    @Published private(set) var lessonsByID: [UUID: Lesson] = [:]
    @Published private(set) var studentsByID: [UUID: Student] = [:]
    @Published private(set) var studentLessonsByID: [UUID: StudentLesson] = [:]
    @Published private(set) var studentLessonSnapshotsByID: [UUID: StudentLessonSnapshot] = [:]

    private let initialCompletedStudentIDs: Set<UUID>
    @Published private(set) var stagedCompletedStudentIDs: Set<UUID>

    struct CheckInDraft: Identifiable, Equatable {
        let id: UUID
        var date: Date
        var status: WorkCheckInStatus
        var purpose: String
        var note: String
        var isNew: Bool
    }

    @Published private(set) var checkIns: [CheckInDraft] = []
    private var deletedCheckInIDs: Set<UUID> = []

    init(work: WorkModel) {
        self.work = work

        self.title = work.title
        self.notes = work.notes
        self.workType = work.workType
        self.selectedStudentIDs = Set(work.studentIDs)
        self.selectedStudentLessonID = work.studentLessonID
        self.completedAt = work.completedAt

        let initiallyCompleted = work.studentIDs.filter { work.isStudentCompleted($0) }
        self.initialCompletedStudentIDs = Set(initiallyCompleted)
        self.stagedCompletedStudentIDs = Set(initiallyCompleted)

        self.checkIns = work.checkIns.map {
            CheckInDraft(
                id: $0.id,
                date: $0.date,
                status: $0.status,
                purpose: $0.purpose,
                note: $0.note,
                isNew: false
            )
        }
    }

    func rebuildCaches(lessons: [Lesson], students: [Student], studentLessons: [StudentLesson]) {
        lessonsByID = Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })
        studentsByID = Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) })
        studentLessonsByID = Dictionary(uniqueKeysWithValues: studentLessons.map { ($0.id, $0) })
        studentLessonSnapshotsByID = Dictionary(
            uniqueKeysWithValues: studentLessons.map { ($0.id, $0.snapshot()) }
        )
    }

    func isStudentCompletedDraft(_ id: UUID) -> Bool {
        stagedCompletedStudentIDs.contains(id)
    }

    func setStudentCompletedDraft(_ id: UUID, _ completed: Bool) {
        if completed {
            stagedCompletedStudentIDs.insert(id)
        } else {
            stagedCompletedStudentIDs.remove(id)
        }
    }

    func addCheckInDraft(date: Date, purpose: String, note: String) {
        let draft = CheckInDraft(
            id: UUID(),
            date: date,
            status: .scheduled,
            purpose: purpose,
            note: note,
            isNew: true
        )
        checkIns.append(draft)
    }

    func setCheckInDraftStatus(_ draftID: UUID, to status: WorkCheckInStatus) {
        guard let index = checkIns.firstIndex(where: { $0.id == draftID }) else { return }
        checkIns[index].status = status
    }

    func updateCheckInDraft(_ updated: CheckInDraft) {
        guard let index = checkIns.firstIndex(where: { $0.id == updated.id }) else { return }
        checkIns[index] = updated
    }

    func deleteCheckInDraft(_ draft: CheckInDraft) {
        if draft.isNew {
            checkIns.removeAll(where: { $0.id == draft.id })
        } else {
            deletedCheckInIDs.insert(draft.id)
            checkIns.removeAll(where: { $0.id == draft.id })
        }
    }

    func save(modelContext: ModelContext) {
        work.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        work.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        work.workType = workType
        work.completedAt = completedAt

        work.studentIDs = Array(selectedStudentIDs)
        work.studentLessonID = selectedStudentLessonID

        work.ensureParticipantsFromStudentIDs()

        // Reconcile per-student completion state
        for studentID in stagedCompletedStudentIDs {
            if initialCompletedStudentIDs.contains(studentID) {
                // already completed, do nothing
                continue
            } else {
                // mark as completed now
                work.markStudent(studentID, completedAt: Date())
            }
        }

        for studentID in initialCompletedStudentIDs.subtracting(stagedCompletedStudentIDs) {
            // clear completion
            work.markStudent(studentID, completedAt: nil)
        }

        // Reconcile check-ins
        // Delete check-ins
        for deletedID in deletedCheckInIDs {
            if let checkIn = work.checkIns.first(where: { $0.id == deletedID }) {
                modelContext.delete(checkIn)
                if let idx = work.checkIns.firstIndex(of: checkIn) {
                    work.checkIns.remove(at: idx)
                }
            }
        }
        deletedCheckInIDs.removeAll()

        // Update existing and add new check-ins
        for draft in checkIns {
            if draft.isNew {
                let newCheckIn = WorkCheckIn(workID: work.id, date: draft.date, status: draft.status, purpose: draft.purpose, note: draft.note, work: work)
                modelContext.insert(newCheckIn)
                work.checkIns.append(newCheckIn)
            } else {
                if let existingCheckIn = work.checkIns.first(where: { $0.id == draft.id }) {
                    existingCheckIn.date = draft.date
                    existingCheckIn.status = draft.status
                    existingCheckIn.purpose = draft.purpose
                    existingCheckIn.note = draft.note
                }
            }
        }

        try? modelContext.save()
    }

    func deleteWork(modelContext: ModelContext) {
        modelContext.delete(work)
        try? modelContext.save()
    }
}
