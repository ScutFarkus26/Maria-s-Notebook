// WorkDetailViewModel+Peers.swift
// Who else is on a work item: Working With, Project Group, Lesson Cohort,
// Awaiting Follow-Up and Group Meeting.
//
// Every list names children still in the room and not hidden as test
// students. They used to read every child on file, so a child who had left
// was listed and booked into Group Meetings, and hidden test students showed
// in the cohort (bug hunt 2026-11-03 #36).

import CoreData
import Foundation

extension WorkDetailViewModel {

    func loadPeerData(for workModel: CDWorkModel, modelContext: NSManagedObjectContext) {
        let owner = WorkGrouping.owner(of: workModel)
        let primaryStudentID = workModel.studentID
        let rowPeers = Self.rowPeers(of: workModel, in: modelContext)
        let projectMemberIDs = Self.projectMemberIDs(of: workModel, excluding: owner, in: modelContext)

        // All work items for the same lesson by other students, each child's
        // open row first and then her newest, so the cohort row and the tap
        // target show the work she is on, not whichever row came back first.
        let allWork = modelContext.safeFetch(CDFetchRequest(CDWorkModel.self))
        let peerWorks = Self.preferredFirst(allWork
            .filter { $0.lessonID == workModel.lessonID && $0.studentID != primaryStudentID })
        let peerWorkStudentIDs = Set(peerWorks.compactMap { UUID(uuidString: $0.studentID) })

        // Lesson recipients who don't have work yet (awaiting follow-up)
        let awaitingFollowUpIDs = recipientIDs(of: workModel, excluding: primaryStudentID)
            .subtracting(peerWorkStudentIDs)

        var allPeerStudentIDs = Set(rowPeers.working).union(rowPeers.meeting)
        allPeerStudentIDs.formUnion(projectMemberIDs)
        allPeerStudentIDs.formUnion(peerWorkStudentIDs)
        allPeerStudentIDs.formUnion(awaitingFollowUpIDs)
        let classmates = classmatesByID(allPeerStudentIDs, in: modelContext)

        workParticipants = rowPeers.working.compactMap { id in
            classmates[id].map { (student: $0, completedAt: rowPeers.completedAt[id] ?? nil) }
        }
        groupMeetingPeers = rowPeers.meeting.compactMap { classmates[$0] }
        projectGroupMembers = projectMemberIDs
            .compactMap { classmates[$0] }
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

        // A child already shown with this work isn't listed again in the cohort.
        let shown = projectMemberIDs.union(workParticipants.compactMap(\.student.id))
        lessonCohort = Self.cohort(
            of: peerWorks, allWork: allWork, classmates: classmates, skipping: shown, lessons: relatedLessons
        )

        awaitingFollowUp = awaitingFollowUpIDs
            .compactMap { classmates[$0] }
            .sorted { $0.firstName < $1.firstName }
    }

    /// Open rows before closed ones, then newest first: the order the cohort
    /// and the tap targets take each child's first row in.
    static func preferredFirst(_ works: [CDWorkModel]) -> [CDWorkModel] {
        works.sorted { lhs, rhs in
            if lhs.status.isOpen != rhs.status.isOpen { return lhs.status.isOpen }
            return (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
        }
    }

    // MARK: - Who is on the row

    private struct RowPeers {
        /// Working With: the other children on a genuinely shared row.
        let working: [UUID]
        /// Group Meeting: the other children this work is with.
        let meeting: [UUID]
        /// When each child on the row finished her part.
        let completedAt: [UUID: Date?]
    }

    /// The other children on this row. Working With lists them only when the
    /// row is genuinely shared: Quick New Work's copies name each other too,
    /// but each child works on her own copy, where her status is, so her name
    /// on this one never read finished and she was listed twice, here and in
    /// the cohort. A linked copy's classmates are in the cohort, from their
    /// own copies; a Group Meeting still asks all of them.
    private static func rowPeers(of work: CDWorkModel, in context: NSManagedObjectContext) -> RowPeers {
        let owner = WorkGrouping.owner(of: work)
        let group = WorkGrouping.group(containing: work, in: context)
        if case .linkedCopies = group.shape {
            let copyOwners = group.siblings.compactMap(WorkGrouping.owner(of:)).filter { $0 != owner }
            return RowPeers(working: [], meeting: copyOwners, completedAt: [:])
        }
        let others = WorkGrouping.studentIDs(of: work).filter { $0 != owner }
        let completedAt = Dictionary(
            WorkLogService.participants(of: work).compactMap { participant in
                UUID(uuidString: participant.studentID).map { ($0, participant.completedAt) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        return RowPeers(working: others, meeting: others, completedAt: completedAt)
    }

    /// The other members of the project this work came from (its
    /// `sourceContextID` names a project session). A classmate with project
    /// work of her own on the lesson isn't one: the fallback that counted
    /// every such child is gone, and the children on the same shared row are
    /// under Working With.
    private static func projectMemberIDs(
        of work: CDWorkModel, excluding owner: UUID?, in context: NSManagedObjectContext
    ) -> Set<UUID> {
        guard work.sourceContextType == .projectSession,
              let sessionIDString = work.sourceContextID,
              let sessionID = UUID(uuidString: sessionIDString),
              let project = context.object(CDProjectSession.self, id: sessionID)?.project else { return [] }
        return Set(project.memberStudentUUIDs.filter { $0 != owner })
    }

    /// Everyone given this work's lesson, but its own child.
    private func recipientIDs(of work: CDWorkModel, excluding primaryStudentID: String) -> Set<UUID> {
        var ids = Set<UUID>()
        for la in relatedLessonAssignments where la.lessonID == work.lessonID && la.state == .presented {
            ids.formUnion(la.resolvedStudentIDs.filter { $0.uuidString != primaryStudentID })
        }
        return ids
    }

    /// The children among `ids` still in the room and not hidden as test
    /// students. A child who has left keeps her rows, but isn't a classmate
    /// to work with, compare with or book a meeting with.
    private func classmatesByID(_ ids: Set<UUID>, in context: NSManagedObjectContext) -> [UUID: CDStudent] {
        guard !ids.isEmpty else { return [:] }
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = NSPredicate(format: "id IN %@", Array(ids))
        let visible = TestStudentsFilter.filterVisible(
            context.safeFetch(request).filter(\.isEnrolled),
            show: testStudentSettings?.show,
            namesRaw: testStudentSettings?.names
        )
        return Dictionary(
            visible.compactMap { student in student.id.map { ($0, student) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    // MARK: - Lesson Cohort

    /// Classmates with work on the same lesson, with what each is on now.
    private static func cohort(
        of peerWorks: [CDWorkModel],
        allWork: [CDWorkModel],
        classmates: [UUID: CDStudent],
        skipping shown: Set<UUID>,
        lessons: [CDLesson]
    ) -> [LessonCohortEntry] {
        let lessonsByIDString: [String: CDLesson] = Dictionary(
            lessons.compactMap { lesson in lesson.id.map { ($0.uuidString, lesson) } },
            uniquingKeysWith: { first, _ in first }
        )
        var seenStudentIDs = shown
        var entries: [LessonCohortEntry] = []
        for w in peerWorks {
            guard let studentUUID = UUID(uuidString: w.studentID),
                  let student = classmates[studentUUID],
                  seenStudentIDs.insert(studentUUID).inserted else { continue }
            entries.append(LessonCohortEntry(
                student: student,
                status: w.status,
                currentWorkTitle: w.status.isClosed
                    ? currentWorkTitle(of: w.studentID, among: allWork, lessons: lessonsByIDString)
                    : nil
            ))
        }
        return entries.sorted {
            if $0.sortKey != $1.sortKey { return $0.sortKey < $1.sortKey }
            return $0.student.firstName < $1.student.firstName
        }
    }

    /// For a classmate who finished this lesson: the lesson of her open work
    /// earliest in this sequence, the one she is on now.
    private static func currentWorkTitle(
        of studentID: String, among allWork: [CDWorkModel], lessons: [String: CDLesson]
    ) -> String? {
        allWork
            .filter { $0.studentID == studentID && $0.status.isOpen }
            .compactMap { lessons[$0.lessonID] }
            .min { $0.orderInSequence < $1.orderInSequence }?
            .name
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
        case .mastered, .keepPracticing, .incomplete, .done: return 2
        }
    }
}
