import Foundation
import OSLog
import CoreData
import SwiftUI

@Observable
@MainActor
final class WorkDetailViewModel {
    private static let logger = Logger.work

    // MARK: - State
    var work: CDWorkModel?
    var relatedLesson: CDLesson?
    var relatedLessons: [CDLesson] = []
    var relatedStudent: CDStudent?
    var workModelNotes: [CDNote] = []
    var relatedPresentation: CDLessonAssignment?
    var relatedLessonAssignments: [CDLessonAssignment] = []
    var resolvedPresentationID: UUID?
    // PERF: Cached UUID parses to avoid repeated UUID(uuidString:) in body-path computed properties
    var resolvedLessonID: UUID?
    var resolvedStudentID: UUID?

    // Peer context
    var workParticipants: [(student: CDStudent, completedAt: Date?)] = []  // work-level collaborators
    var projectGroupMembers: [CDStudent] = []  // other students in the same project
    var lessonCohort: [LessonCohortEntry] = []  // progression peers with context
    var awaitingFollowUp: [CDStudent] = []  // received lesson but no work yet
    var peerWorkIDs: [UUID: UUID] = [:]  // studentID → workID for tap navigation

    var showPresentationNotes = false
    var showAddNoteSheet = false
    var noteBeingEdited: CDNote?
    var showScheduleSheet = false
    var showPlannedBanner = false
    var showDeleteAlert = false
    var showAddStepSheet = false
    var stepBeingEdited: CDWorkStep?
    var showPracticeSessionSheet = false
    var showUnlockNextLessonAlert = false
    var nextLessonToUnlock: CDLesson?

    var status: WorkStatus = .active
    var workKind: WorkKind = .practiceLesson
    var workTitle: String = ""
    var checkInStyle: CheckInStyle = .flexible
    var completionOutcome: CompletionOutcome?
    var completionNote: String = ""

    var newPlanDate: Date = Date()
    var newPlanPurpose: String = "progressCheck"
    var newPlanNote: String = ""
    
    // MARK: - Dependencies
    private let workID: UUID
    private var modelContext: NSManagedObjectContext?
    private var saveCoordinator: SaveCoordinator?
    
    // MARK: - Initialization
    init(workID: UUID) {
        self.workID = workID
    }

    // MARK: - Error Handling Helpers

    private func safeFetch<T: NSManagedObject>(
        _ request: NSFetchRequest<T>,
        context: NSManagedObjectContext,
        functionName: String = #function
    ) -> [T] {
        do {
            return try context.fetch(request)
        } catch {
            Self.logger.warning("\(functionName): Failed to fetch \(T.self): \(error)")
            return []
        }
    }

    // MARK: - Computed Properties
    func scheduleDates(checkIns: [CDWorkCheckIn]) -> WorkScheduleDates {
        WorkScheduleDateLogic.compute(forCheckIns: checkIns)
    }
    
    // PERF: Uses pre-fetched relatedLessons (same subject+group) instead of all lessons
    func likelyNextLesson() -> CDLesson? {
        guard let currentLesson = relatedLesson else { return nil }
        return PlanNextLessonService.findNextLesson(
            after: currentLesson,
            in: relatedLessons
        )
    }
    
    func practiceSessions(allSessions: [CDPracticeSession]) -> [CDPracticeSession] {
        guard let work else { return [] }
        let workIDString = (work.id ?? UUID()).uuidString
        return allSessions
            .filter { $0.workItemIDsArray.contains(workIDString) }
            .sorted { ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast) }
    }
    
    // MARK: - Data Loading
    func loadWork(modelContext: NSManagedObjectContext, saveCoordinator: SaveCoordinator) {
        self.modelContext = modelContext
        self.saveCoordinator = saveCoordinator
        
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "id == %@", workID as CVarArg)
        request.fetchLimit = 1

        let fetchedWork = safeFetch(request, context: modelContext).first
        guard let fetchedWork else {
            return
        }
        
        self.work = fetchedWork
        self.status = fetchedWork.status
        self.workTitle = fetchedWork.title
        self.workKind = fetchedWork.kind ?? .practiceLesson
        self.checkInStyle = fetchedWork.checkInStyle
        self.completionOutcome = fetchedWork.completionOutcome
        // PERF: Parse UUIDs once on load instead of on every body evaluation
        self.resolvedLessonID = UUID(uuidString: fetchedWork.lessonID)
        self.resolvedStudentID = UUID(uuidString: fetchedWork.studentID)
        
        loadRelatedData(for: fetchedWork, modelContext: modelContext)
        loadWorkNotes(for: fetchedWork)
        resolvePresentationID(for: fetchedWork, modelContext: modelContext)
    }
    
    private func loadRelatedData(for workModel: CDWorkModel?, modelContext: NSManagedObjectContext) {
        guard let workModel else { return }
        
        // Load student
        if let studentID = UUID(uuidString: workModel.studentID) {
            let studentRequest = CDFetchRequest(CDStudent.self)
            studentRequest.predicate = NSPredicate(format: "id == %@", studentID as CVarArg)
            studentRequest.fetchLimit = 1
            relatedStudent = safeFetch(studentRequest, context: modelContext).first
        }

        // Load lesson
        if let lessonID = UUID(uuidString: workModel.lessonID) {
            let lessonRequest = CDFetchRequest(CDLesson.self)
            lessonRequest.predicate = NSPredicate(format: "id == %@", lessonID as CVarArg)
            lessonRequest.fetchLimit = 1
            relatedLesson = safeFetch(lessonRequest, context: modelContext).first
        }

        // Load related lessons
        if let currentLesson = relatedLesson {
            let subject = currentLesson.subject.trimmed()
            let group = currentLesson.group.trimmed()

            let lessonRequest = CDFetchRequest(CDLesson.self)
            lessonRequest.predicate = NSPredicate(format: "subject CONTAINS %@ AND group CONTAINS %@", subject, group)
            relatedLessons = safeFetch(lessonRequest, context: modelContext)
        }

        // PERF: Load only lesson assignments for lessons in the same subject+group
        // instead of loading all LessonAssignments via @Query
        if !relatedLessons.isEmpty {
            let relatedLessonIDs = Set(relatedLessons.compactMap { $0.id?.uuidString })
            let allLARequest = CDFetchRequest(CDLessonAssignment.self)
            let allLAs = safeFetch(allLARequest, context: modelContext)
            relatedLessonAssignments = allLAs.filter { la in
                relatedLessonIDs.contains(la.lessonID)
            }
        }

        // Load presentation
        relatedPresentation = workModel.fetchPresentation(from: modelContext)

        // Load peer context
        loadPeerData(for: workModel, modelContext: modelContext)
    }

    // swiftlint:disable:next function_body_length
    private func loadPeerData(for workModel: CDWorkModel, modelContext: NSManagedObjectContext) {
        let primaryStudentID = workModel.studentID

        // 1. Work participants
        let participants = (workModel.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []
        let otherParticipants = participants.filter { $0.studentID != primaryStudentID }
        let participantIDs = otherParticipants.compactMap { UUID(uuidString: $0.studentID) }

        // 2. Project members (via sourceContextID → CDProjectSession → CDProject)
        var projectMemberIDs = Set<UUID>()
        if workModel.sourceContextType == .projectSession,
           let sessionIDString = workModel.sourceContextID,
           let sessionID = UUID(uuidString: sessionIDString) {
            let sessionRequest = CDFetchRequest(CDProjectSession.self)
            sessionRequest.predicate = NSPredicate(format: "id == %@", sessionID as CVarArg)
            sessionRequest.fetchLimit = 1
            if let project = safeFetch(sessionRequest, context: modelContext).first?.project {
                projectMemberIDs = Set(
                    project.memberStudentUUIDs.filter { $0.uuidString != primaryStudentID }
                )
            }
        }

        // 3. Fetch all work items for the same lesson by other students
        let allWorkRequest = CDFetchRequest(CDWorkModel.self)
        let allWork = safeFetch(allWorkRequest, context: modelContext)
        let peerWorks = allWork
            .filter { $0.lessonID == workModel.lessonID && $0.studentID != primaryStudentID }
        let peerWorkStudentIDs = Set(peerWorks.compactMap { UUID(uuidString: $0.studentID) })

        // 2b. Fallback for project work: if no project members found via sourceContextID,
        // treat other students with project-kind work for the same lesson as the project group
        if projectMemberIDs.isEmpty && workModel.kind == .research {
            let projectPeerIDs = peerWorks
                .filter { $0.kind == .research }
                .compactMap { UUID(uuidString: $0.studentID) }
            projectMemberIDs = Set(projectPeerIDs)
        }

        // 4. Lesson recipients who don't have work yet (awaiting follow-up)
        let sameLessonAssignments = relatedLessonAssignments.filter {
            $0.lessonID == workModel.lessonID && $0.state == .presented
        }
        var allLessonRecipientIDs = Set<UUID>()
        for la in sameLessonAssignments {
            let studentIDs = la.studentUUIDs.filter { $0.uuidString != primaryStudentID }
            allLessonRecipientIDs.formUnion(studentIDs)
        }
        let awaitingFollowUpIDs = allLessonRecipientIDs.subtracting(peerWorkStudentIDs)

        // Collect all peer student IDs we need to resolve
        var allPeerStudentIDs = Set<UUID>()
        allPeerStudentIDs.formUnion(participantIDs)
        allPeerStudentIDs.formUnion(projectMemberIDs)
        allPeerStudentIDs.formUnion(peerWorkStudentIDs)
        allPeerStudentIDs.formUnion(awaitingFollowUpIDs)

        guard !allPeerStudentIDs.isEmpty else { return }

        // Batch-fetch all students
        let allStudents = safeFetch(CDFetchRequest(CDStudent.self), context: modelContext)
        let studentsByID = Dictionary(
            allStudents.compactMap { s in s.id.map { ($0, s) } },
            uniquingKeysWith: { first, _ in first }
        )

        // Build lesson lookup for progression context
        let lessonsByIDString: [String: CDLesson] = Dictionary(
            relatedLessons.compactMap { l -> (String, CDLesson)? in
                guard let idStr = l.id?.uuidString else { return nil }
                return (idStr, l)
            },
            uniquingKeysWith: { first, _ in first }
        )

        // Resolve work participants (project collaborators)
        let participantCompletedAt = Dictionary(
            otherParticipants.compactMap { p in UUID(uuidString: p.studentID).map { ($0, p.completedAt) } },
            uniquingKeysWith: { first, _ in first }
        )
        workParticipants = participantIDs.compactMap { id in
            guard let student = studentsByID[id] else { return nil }
            return (student: student, completedAt: participantCompletedAt[id] ?? nil)
        }

        // Resolve project group members
        projectGroupMembers = projectMemberIDs
            .compactMap { studentsByID[$0] }
            .sorted { $0.firstName < $1.firstName }

        // Build peer work ID lookup for tap navigation
        peerWorkIDs = Dictionary(
            peerWorks.compactMap { w in
                guard let studentUUID = UUID(uuidString: w.studentID),
                      let workUUID = w.id else { return nil }
                return (studentUUID, workUUID)
            },
            uniquingKeysWith: { first, _ in first }
        )

        // Build lesson cohort — peers with work for same lesson, with progression context
        // Exclude students already shown in the project group card
        var seenStudentIDs = projectMemberIDs
        var cohortEntries: [LessonCohortEntry] = []
        for w in peerWorks {
            guard let studentUUID = UUID(uuidString: w.studentID),
                  let student = studentsByID[studentUUID] else { continue }
            guard seenStudentIDs.insert(studentUUID).inserted else { continue }

            var currentWorkTitle: String?
            if w.status == .complete {
                // Find their current active work in the same subject/group progression
                let progressionWork = allWork
                    .filter { $0.studentID == w.studentID && $0.status != .complete }
                    .compactMap { (aw: CDWorkModel) -> (lessonID: String, order: Int64)? in
                        guard let lesson = lessonsByIDString[aw.lessonID] else { return nil }
                        return (lessonID: aw.lessonID, order: lesson.orderInGroup)
                    }
                    .min { $0.order < $1.order }

                if let pw = progressionWork {
                    currentWorkTitle = lessonsByIDString[pw.lessonID]?.name
                }
            }

            cohortEntries.append(LessonCohortEntry(
                student: student,
                status: w.status,
                currentWorkTitle: currentWorkTitle
            ))
        }
        lessonCohort = cohortEntries.sorted {
            if $0.sortKey != $1.sortKey { return $0.sortKey < $1.sortKey }
            return $0.student.firstName < $1.student.firstName
        }

        // Resolve awaiting follow-up
        awaitingFollowUp = awaitingFollowUpIDs
            .compactMap { studentsByID[$0] }
            .sorted { $0.firstName < $1.firstName }
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
    
    // MARK: - Actions
    // PERF: Uses pre-loaded relatedLessons and relatedLessonAssignments
    func checkAndOfferUnlock() {
        guard status == .complete,
              completionOutcome == .proficient,
              relatedLesson != nil,
              let studentID = UUID(uuidString: work?.studentID ?? ""),
              let nextLesson = likelyNextLesson() else {
            return
        }

        // Find CDLessonAssignment for next lesson
        let nextLessonAssignment = relatedLessonAssignments.first { la in
            la.lessonIDUUID == nextLesson.id &&
            la.studentUUIDs.contains(studentID)
        }

        // Offer unlock if blocked
        if let la = nextLessonAssignment, !la.manuallyUnblocked && !la.isGiven {
            nextLessonToUnlock = nextLesson
            showUnlockNextLessonAlert = true
        }
    }

    func unlockNextLesson(modelContext: NSManagedObjectContext) {
        guard let lesson = relatedLesson,
              let studentIDString = work?.studentID,
              let studentID = UUID(uuidString: studentIDString) else { return }

        _ = UnlockNextLessonService.unlockNextLesson(
            after: lesson.id ?? UUID(),
            for: Set([studentID]),
            context: modelContext,
            lessons: relatedLessons,
            cdAssignments: relatedLessonAssignments
        )

        showScheduleSheet = true
    }
    
    func addPlan(modelContext: NSManagedObjectContext) {
        guard let work else { return }

        let checkIn = CDWorkCheckIn(context: modelContext)
        checkIn.id = UUID()
        checkIn.workID = work.id?.uuidString ?? ""
        checkIn.date = newPlanDate
        checkIn.status = .scheduled
        checkIn.purpose = newPlanPurpose
        checkIn.work = work

        let trimmedNote = newPlanNote.trimmed()
        if !trimmedNote.isEmpty {
            checkIn.setLegacyNoteText(trimmedNote, in: modelContext)
        }
        showPlannedBanner = true
    }
    
    func save(modelContext: NSManagedObjectContext, saveCoordinator: SaveCoordinator) {
        guard let work else { return }
        
        work.status = status
        work.kind = workKind
        work.title = workTitle
        work.checkInStyle = checkInStyle
        work.completionOutcome = completionOutcome
        
        saveCoordinator.save(modelContext)
    }
    
    func deleteWork(modelContext: NSManagedObjectContext, saveCoordinator: SaveCoordinator, onDeleted: @escaping () -> Void) {
        guard let work else { return }
        
        modelContext.delete(work)
        saveCoordinator.save(modelContext)
        onDeleted()
    }
    
    // MARK: - Helpers
    func studentName() -> String {
        relatedStudent?.firstName ?? "Unknown"
    }
    
    func lessonTitle() -> String {
        relatedLesson?.name ?? "Unknown CDLesson"
    }
    
    func categoryColor(_ category: String) -> Color {
        switch category.lowercased() {
        case "observation": return .blue
        case "practice": return .green
        case "follow-up": return .orange
        case "general": return .gray
        default: return .purple
        }
    }
}

// MARK: - Peer Context Types

struct LessonCohortEntry {
    let student: CDStudent
    let status: WorkStatus
    let currentWorkTitle: String?  // for completed peers: what they're working on now

    var sortKey: Int {
        switch status {
        case .active: return 0
        case .review: return 1
        case .complete: return 2
        }
    }
}
