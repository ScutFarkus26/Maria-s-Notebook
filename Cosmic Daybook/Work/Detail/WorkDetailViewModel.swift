import Foundation
import CoreData
import OSLog
import SwiftUI

@Observable
final class WorkDetailViewModel {
    private static let logger = Logger.work
    // MARK: - State
    var work: CDWorkModel?
    var relatedLesson: CDLesson?
    var relatedLessons: [CDLesson] = []
    var relatedStudent: CDStudent?
    var workModelNotes: [CDNote] = []
    var relatedPresentation: CDLessonAssignment?
    /// The presentation needs giving to this work's child again: the flag
    /// shared by the group, or her own follow-up says re-present.
    var relatedPresentationNeedsAnother = false
    var relatedLessonAssignments: [CDLessonAssignment] = []
    var resolvedPresentationID: UUID?
    // PERF: Cached UUID parses to avoid repeated UUID(uuidString:) in body-path computed properties
    var resolvedLessonID: UUID?
    var resolvedStudentID: UUID?

    // Peer context
    var workParticipants: [(student: CDStudent, completedAt: Date?)] = []  // others on this shared row
    var groupMeetingPeers: [CDStudent] = []  // the others a Group Meeting books, linked copies included
    var projectGroupMembers: [CDStudent] = []  // other students in the same project
    var lessonCohort: [LessonCohortEntry] = []  // progression peers with context
    var awaitingFollowUp: [CDStudent] = []  // received lesson but no work yet
    var peerWorkIDs: [UUID: UUID] = [:]  // studentID → workID for tap navigation

    var editingNoteCheckIn: CDWorkCheckIn?
    var editingNoteDraft: String = ""
    var showEditNoteAlert = false
    var showPlannedBanner = false
    var showDeleteAlert = false
    var showUnlockNextLessonAlert = false
    var nextLessonToUnlock: CDLesson?
    /// A check-in or note whose trash button was tapped, waiting on the
    /// page's question before it goes (bug hunt 2026-11-03 #35).
    var checkInPendingDelete: CDWorkCheckIn?
    var notePendingDelete: CDNote?

    var status: WorkStatus = .active
    var workKind: WorkKind = .practiceLesson
    var workTitle: String = ""
    var checkInStyle: CheckInStyle = .flexible
    var completionNote: String = ""

    /// What the row held when the page last read it: on load, and again when
    /// the row changes underneath (`refreshHeaderFromStore`). A header field
    /// still equal to its stored value is one the guide hasn't changed in
    /// this sitting, and Save leaves it alone, so a status or title set
    /// elsewhere while the page was open (the grid, Claude, another device)
    /// isn't written back over (bug hunt 2026-11-03 #33).
    private(set) var storedStatus: WorkStatus = .active
    private(set) var storedTitle: String = ""
    private(set) var storedKind: WorkKind = .practiceLesson
    private(set) var storedCheckInStyle: CheckInStyle = .flexible

    /// The pills the header offers: every status a guide can choose, Finished
    /// among them since 2026-10-13.
    var statusChoices: [WorkStatus] { WorkStatus.pickable }

    /// The day picked for a new check-in. Nil until one is picked, meaning
    /// today, read when the check-in is added: a default taken when the page
    /// opened offered yesterday on a page left open overnight (#45).
    var newPlanDate: Date?
    var newPlanPurpose: String = "progressCheck"
    var newPlanNote: String = ""

    /// The test-student setting the peer lists hide by; nil reads the
    /// guide's own setting. Tests pin it.
    var testStudentSettings: (show: Bool, names: String)?

    // MARK: - Dependencies
    private let workID: UUID
    private var modelContext: NSManagedObjectContext?
    private var saveCoordinator: SaveCoordinator?
    
    // MARK: - Initialization
    init(workID: UUID) {
        self.workID = workID
    }

    // MARK: - Computed Properties
    
    // PERF: Uses pre-fetched relatedLessons (same area+sequence) instead of all lessons
    func likelyNextLesson() -> CDLesson? {
        guard let currentLesson = relatedLesson else { return nil }
        return PlanNextLessonService.findNextLesson(
            after: currentLesson,
            in: relatedLessons
        )
    }
    
    /// This work's practice check-ins, newest first.
    func practiceCheckIns(in context: NSManagedObjectContext) -> [CDWorkCheckIn] {
        guard let work else { return [] }
        return WorkLogService.checkIns(of: work, in: context)
            .filter(\.isPractice)
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
    
    // MARK: - Data Loading
    func loadWork(modelContext: NSManagedObjectContext, saveCoordinator: SaveCoordinator) {
        self.modelContext = modelContext
        self.saveCoordinator = saveCoordinator
        
        guard let fetchedWork = modelContext.object(CDWorkModel.self, id: workID) else {
            return
        }
        
        self.work = fetchedWork
        self.status = fetchedWork.status
        self.workTitle = fetchedWork.title
        self.workKind = fetchedWork.displayKind
        self.checkInStyle = fetchedWork.checkInStyle
        rememberStored(from: fetchedWork)
        // PERF: Parse UUIDs once on load instead of on every body evaluation
        self.resolvedLessonID = UUID(uuidString: fetchedWork.lessonID)
        self.resolvedStudentID = UUID(uuidString: fetchedWork.studentID)
        
        loadRelatedData(for: fetchedWork, modelContext: modelContext)
        loadWorkNotes(for: fetchedWork)
        resolvePresentationID(for: fetchedWork, modelContext: modelContext)
    }

    /// Notes what the row holds now as the header's stored values.
    func rememberStored(from work: CDWorkModel) {
        storedStatus = work.status
        storedTitle = work.title
        storedKind = work.displayKind
        storedCheckInStyle = work.checkInStyle
    }

    /// Reads the row again for the header fields the guide hasn't changed in
    /// this sitting, so a status or title set elsewhere shows here, and Save
    /// doesn't write the old one back. A field she has changed keeps her edit,
    /// and Save writes it.
    func refreshHeaderFromStore() {
        guard let work, !work.isDeleted, work.managedObjectContext != nil else { return }
        if status == storedStatus, status != work.status { status = work.status }
        if workTitle == storedTitle, workTitle != work.title { workTitle = work.title }
        if workKind == storedKind, workKind != work.displayKind { workKind = work.displayKind }
        if checkInStyle == storedCheckInStyle, checkInStyle != work.checkInStyle {
            checkInStyle = work.checkInStyle
        }
        rememberStored(from: work)
    }

    /// Re-reads the plans of this work's sequence. Unlock reads them, and
    /// they change when it makes her a draft: a list read only when the page
    /// opened offered the unlock again and made a second draft (#34).
    func reloadLessonAssignments() {
        guard let modelContext else { return }
        let relatedLessonIDs = relatedLessons.compactMap { $0.id?.uuidString }
        guard !relatedLessonIDs.isEmpty else {
            relatedLessonAssignments = []
            return
        }
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID IN %@", relatedLessonIDs)
        relatedLessonAssignments = modelContext.safeFetch(request)
    }

    private func loadRelatedData(for workModel: CDWorkModel?, modelContext: NSManagedObjectContext) {
        guard let workModel else { return }
        
        // Load student
        if let studentID = UUID(uuidString: workModel.studentID) {
            relatedStudent = modelContext.object(CDStudent.self, id: studentID)
        }

        // Load lesson
        if let lessonID = UUID(uuidString: workModel.lessonID) {
            relatedLesson = modelContext.object(CDLesson.self, id: lessonID)
        }

        // Load related lessons
        if let currentLesson = relatedLesson {
            let area = currentLesson.area.trimmed()
            let sequence = currentLesson.sequence.trimmed()

            let lessonRequest = CDFetchRequest(CDLesson.self)
            lessonRequest.predicate = NSPredicate(format: "area CONTAINS %@ AND sequence CONTAINS %@", area, sequence)
            relatedLessons = modelContext.safeFetch(lessonRequest)
        }

        // PERF: Load only lesson assignments for lessons in the same area+sequence
        // instead of loading all LessonAssignments via @Query
        reloadLessonAssignments()

        // Load presentation
        relatedPresentation = workModel.fetchPresentation(from: modelContext)
        relatedPresentationNeedsAnother = relatedPresentation.map { presentation in
            let representations = presentation.id.map {
                ChildRepresentations(presentationIDs: [$0.uuidString], in: modelContext)
            } ?? .none
            return presentation.needsAnotherPresentation(for: workModel.studentID, given: representations)
        } ?? false

        // Load peer context
        loadPeerData(for: workModel, modelContext: modelContext)
    }

    /// Re-reads the notes list only. Note actions call this rather than
    /// `loadWork`, which also resets the title, kind, status and check-in
    /// style fields to the stored row and threw away edits waiting for Save
    /// (and then filed a pending status note as a plain note).
    func reloadNotes() {
        loadWorkNotes(for: work)
    }

    private func loadWorkNotes(for workModel: CDWorkModel?) {
        guard let workModel else { return }
        workModelNotes = ((workModel.unifiedNotes?.allObjects as? [CDNote]) ?? [])
            .sorted { ($0.createdAt ?? Date.distantPast) > ($1.createdAt ?? Date.distantPast) }
    }
    
    private func resolvePresentationID(for workModel: CDWorkModel?, modelContext: NSManagedObjectContext) {
        guard let workModel else { return }
        
        if let presentationIDString = workModel.presentationID,
           let uuid = UUID(uuidString: presentationIDString) {
            resolvedPresentationID = uuid
        }
    }
    
}
