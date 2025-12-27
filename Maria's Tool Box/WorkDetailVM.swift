import SwiftUI
import SwiftData
import Foundation
import Combine

/// View Model for editing or viewing the details of a WorkModel.
@MainActor
final class WorkDetailViewModel: ObservableObject {
    let work: WorkModel

    @Published var title: String
    @Published var notes: String
    @Published var workType: WorkModel.WorkType
    @Published var selectedStudentIDs: Set<UUID>
    @Published var selectedStudentLessonID: UUID?
    @Published var completedAt: Date?

    // Cache maps for lookup
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
        
        // Load participants
        let participantIDs = (work.participants ?? []).map { $0.studentID }
        self.selectedStudentIDs = Set(participantIDs)
        
        self.selectedStudentLessonID = work.studentLessonID
        self.completedAt = work.completedAt

        // Load completion state
        let initiallyCompleted = (work.participants ?? []).filter { $0.completedAt != nil }.map { $0.studentID }
            
        self.initialCompletedStudentIDs = Set(initiallyCompleted)
        self.stagedCompletedStudentIDs = Set(initiallyCompleted)

        self.checkIns = (work.checkIns ?? []).map {
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

    // MARK: - Computed Properties for View
    
    var selectedStudentsList: [Student] {
        selectedStudentIDs.compactMap { studentsByID[$0] }
            .sorted { $0.firstName < $1.firstName }
    }
    
    var subject: String {
        if let lid = selectedStudentLessonID, let l = lessonsByID[lid] {
            return l.subject
        }
        return ""
    }

    // MARK: - Actions

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

    // Schedules a future check-in
    func addScheduledCheckInDraft(date: Date, purpose: String) {
        let draft = CheckInDraft(
            id: UUID(),
            date: date,
            status: .scheduled,
            purpose: purpose,
            note: "",
            isNew: true
        )
        checkIns.append(draft)
    }
    
    // Logs an immediate (unscheduled) check-in
    func addInstantCheckIn(note: String) {
        let draft = CheckInDraft(
            id: UUID(),
            date: Date(),
            status: .completed,
            purpose: "Quick Check-in",
            note: note,
            isNew: true
        )
        checkIns.append(draft)
    }

    // Completes a scheduled check-in with a note and updates date to now
    func completeCheckIn(draftID: UUID, note: String) {
        guard let index = checkIns.firstIndex(where: { $0.id == draftID }) else { return }
        var updated = checkIns[index]
        updated.status = .completed
        updated.note = note
        updated.date = Date() // Reset date to the moment it was actually done
        checkIns[index] = updated
    }

    func setCheckInDraftStatus(_ draftID: UUID, to status: WorkCheckInStatus) {
        guard let index = checkIns.firstIndex(where: { $0.id == draftID }) else { return }
        checkIns[index].status = status
    }
    
    func updateCheckInNote(_ id: UUID, note: String) {
        guard let index = checkIns.firstIndex(where: { $0.id == id }) else { return }
        checkIns[index].note = note
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
        
        work.studentLessonID = selectedStudentLessonID

        // 1. Reconcile Participants (Remove unselected)
        let currentParticipantIDs = Set((work.participants ?? []).map { $0.studentID })
        let toRemove = currentParticipantIDs.subtracting(selectedStudentIDs)
        
        for studentID in toRemove {
            if let participant = work.participant(for: studentID) {
                modelContext.delete(participant)
                let current = work.participants ?? []
                let updated = current.filter { $0.id != participant.id }
                work.participants = updated
            }
        }

        // 2. Reconcile Additions & Completion State
        for studentID in selectedStudentIDs {
            let shouldBeCompleted = stagedCompletedStudentIDs.contains(studentID)
            
            if shouldBeCompleted {
                let existingDate = work.participant(for: studentID)?.completedAt
                work.markStudent(studentID, completedAt: existingDate ?? Date())
            } else {
                work.markStudent(studentID, completedAt: nil)
            }
        }

        // Reconcile check-ins
        for deletedID in deletedCheckInIDs {
            if let checkIn = (work.checkIns ?? []).first(where: { $0.id == deletedID }) {
                modelContext.delete(checkIn)
                let updated = (work.checkIns ?? []).filter { $0.id != checkIn.id }
                work.checkIns = updated
            }
        }
        deletedCheckInIDs.removeAll()

        for draft in checkIns {
            if draft.isNew {
                let newCheckIn = WorkCheckIn(workID: work.id, date: draft.date, status: draft.status, purpose: draft.purpose, note: draft.note, work: work)
                modelContext.insert(newCheckIn)
                if work.checkIns == nil { work.checkIns = [] }
                work.checkIns = (work.checkIns ?? []) + [newCheckIn]
            } else {
                if let existingCheckIn = (work.checkIns ?? []).first(where: { $0.id == draft.id }) {
                    existingCheckIn.date = draft.date
                    existingCheckIn.status = draft.status
                    existingCheckIn.purpose = draft.purpose
                    existingCheckIn.note = draft.note
                    existingCheckIn.work = work // Ensure relationship
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
