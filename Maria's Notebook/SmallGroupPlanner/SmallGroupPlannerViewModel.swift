// SmallGroupPlannerViewModel.swift
// ViewModel for Small Group Planning Intelligence — computes per-lesson per-student readiness tiers.

import SwiftUI
import CoreData

@Observable @MainActor
final class SmallGroupPlannerViewModel {
    private(set) var candidates: [LessonGroupCandidate] = []
    private(set) var subjects: [String] = []
    private(set) var isLoading = false

    var selectedSubject: String?
    var selectedGroup: String?
    var levelFilter: LevelFilter = .all
    var selectedStudentIDs: Set<UUID> = []

    // MARK: - Computed

    var availableGroups: [String] {
        guard let subject = selectedSubject else { return [] }
        return allGroupsBySubject[subject] ?? []
    }

    var filteredCandidates: [LessonGroupCandidate] {
        candidates.filter { $0.hasOpportunity }
    }

    // MARK: - Private State

    private var allGroupsBySubject: [String: [String]] = [:]
    private var allLessons: [CDLesson] = []
    private var allStudents: [CDStudent] = []
    private var presentedAssignments: [CDLessonAssignment] = []
    private var activeWork: [CDWorkModel] = []

    // MARK: - Load Data

    func loadData(context: NSManagedObjectContext) {
        isLoading = true
        defer { isLoading = false }

        // Fetch all lessons
        let lessonRequest = CDFetchRequest(CDLesson.self)
        allLessons = context.safeFetch(lessonRequest)

        // Fetch enrolled visible students
        let studentRequest = CDFetchRequest(CDStudent.self)
        studentRequest.predicate = NSPredicate(
            format: "enrollmentStatusRaw == %@",
            CDStudent.EnrollmentStatus.enrolled.rawValue
        )
        studentRequest.sortDescriptors = CDStudent.sortByName
        allStudents = TestStudentsFilter.filterVisible(context.safeFetch(studentRequest))

        // Apply level filter
        let filteredStudents: [CDStudent]
        if levelFilter != .all {
            filteredStudents = allStudents.filter { levelFilter.matches($0.level) }
        } else {
            filteredStudents = allStudents
        }

        // Fetch all presented assignments
        let assignmentRequest = CDFetchRequest(CDLessonAssignment.self)
        assignmentRequest.predicate = NSPredicate(
            format: "stateRaw == %@",
            LessonAssignmentState.presented.rawValue
        )
        presentedAssignments = context.safeFetch(assignmentRequest)

        // Fetch active/review work
        let workRequest = CDFetchRequest(CDWorkModel.self)
        activeWork = context.safeFetch(workRequest)

        // Build subject → groups index
        var groupsMap: [String: Set<String>] = [:]
        for lesson in allLessons where !lesson.subject.isEmpty && !lesson.group.isEmpty {
            groupsMap[lesson.subject, default: []].insert(lesson.group)
        }
        subjects = groupsMap.keys.sorted()
        allGroupsBySubject = groupsMap.mapValues { $0.sorted() }

        // Build candidates for selected subject/group
        buildCandidates(students: filteredStudents, context: context)
    }

    // MARK: - Build Candidates

    private func buildCandidates(students: [CDStudent], context: NSManagedObjectContext) {
        guard let subject = selectedSubject, let group = selectedGroup else {
            candidates = []
            return
        }

        // Filter lessons to selected subject/group
        let groupLessons = allLessons
            .filter {
                $0.subject.trimmed().caseInsensitiveCompare(subject) == .orderedSame &&
                $0.group.trimmed().caseInsensitiveCompare(group) == .orderedSame
            }
            .sorted { $0.orderInGroup < $1.orderInGroup }

        guard !groupLessons.isEmpty else {
            candidates = []
            return
        }

        // Build lookup indices
        let _: [UUID: CDLesson] = Dictionary(
            uniqueKeysWithValues: allLessons.compactMap { l in
                guard let id = l.id else { return nil }
                return (id, l)
            }
        )

        // Presented assignments by lessonID
        var presentedByLessonID: [String: [CDLessonAssignment]] = [:]
        for assignment in presentedAssignments {
            let normalized = UUID(uuidString: assignment.lessonID)?.uuidString ?? assignment.lessonID
            presentedByLessonID[normalized, default: []].append(assignment)
        }

        // Work by presentationID
        let workByPresentationID = Dictionary(grouping: activeWork) { $0.presentationID ?? "" }

        // Student ID set for quick lookups
        let studentIDs: [UUID] = students.compactMap(\.id)
        let studentsByID: [UUID: CDStudent] = Dictionary(
            uniqueKeysWithValues: students.compactMap { s in
                guard let id = s.id else { return nil }
                return (id, s)
            }
        )

        var result: [LessonGroupCandidate] = []

        for lesson in groupLessons {
            guard let lessonID = lesson.id else { continue }
            let lessonIDStr = lessonID.uuidString

            // Find preceding lesson
            let precedingLesson = BlockingAlgorithmEngine.findPrecedingLesson(
                currentLesson: lesson, lessons: allLessons
            )
            let precedingLessonName = precedingLesson?.name

            // Find two-before lesson (preceding of preceding)
            let twoBefore: CDLesson?
            if let preceding = precedingLesson {
                twoBefore = BlockingAlgorithmEngine.findPrecedingLesson(
                    currentLesson: preceding, lessons: allLessons
                )
            } else {
                twoBefore = nil
            }

            // Resolve progression rules for preceding lesson
            let rules: LessonProgressionRules.ResolvedRules?
            if let preceding = precedingLesson {
                rules = LessonProgressionRules.resolve(for: preceding, context: context)
            } else {
                rules = nil
            }

            // Presented assignments for preceding lesson
            let precedingAssignments: [CDLessonAssignment]
            if let precedingID = precedingLesson?.id?.uuidString {
                precedingAssignments = presentedByLessonID[precedingID] ?? []
            } else {
                precedingAssignments = []
            }

            // Presented assignments for two-before lesson
            let twoBeforeAssignments: [CDLessonAssignment]
            if let twoBeforeID = twoBefore?.id?.uuidString {
                twoBeforeAssignments = presentedByLessonID[twoBeforeID] ?? []
            } else {
                twoBeforeAssignments = []
            }

            // Which students already have this lesson presented?
            let lessonAssignments = presentedByLessonID[lessonIDStr] ?? []
            let alreadyPresentedStudentIDs: Set<UUID> = {
                var set = Set<UUID>()
                for la in lessonAssignments {
                    for sidStr in la.studentIDs {
                        if let uuid = UUID(uuidString: sidStr) { set.insert(uuid) }
                    }
                }
                return set
            }()

            var readyStudents: [GroupStudentStatus] = []
            var almostReadyStudents: [GroupStudentStatus] = []
            var notReadyCount = 0

            for studentID in studentIDs {
                // Skip if already presented this lesson
                guard !alreadyPresentedStudentIDs.contains(studentID) else { continue }
                guard let student = studentsByID[studentID] else { continue }

                // No preceding lesson = first in sequence = everyone is ready
                guard let preceding = precedingLesson else {
                    readyStudents.append(makeStatus(student: student, tier: .ready, reasons: [], precedingName: nil))
                    continue
                }

                // Check if student has been presented the preceding lesson
                let precedingAssignment = precedingAssignments.first { la in
                    la.studentIDs.contains(studentID.uuidString)
                }

                if let precedingAssignment {
                    // Student has preceding lesson — check gates
                    var reasons: [GroupBlockingReason] = []

                    // Gate 1: Practice completion
                    if let rules, rules.requiresPractice {
                        let presentationID = precedingAssignment.id?.uuidString ?? ""
                        let relatedWork = workByPresentationID[presentationID] ?? []

                        if relatedWork.isEmpty {
                            // No work assigned yet — if practice flagged, not ready
                            if precedingAssignment.needsPractice {
                                reasons.append(.needsPracticeCompletion(
                                    workTitle: preceding.name,
                                    workID: precedingAssignment.id ?? UUID(),
                                    daysSinceAssigned: daysSince(precedingAssignment.presentedAt)
                                ))
                            }
                        } else {
                            for work in relatedWork {
                                if !BlockingAlgorithmEngine.isWorkComplete(work: work, requiredStudentIDs: [studentID]) {
                                    reasons.append(.needsPracticeCompletion(
                                        workTitle: work.title,
                                        workID: work.id ?? UUID(),
                                        daysSinceAssigned: daysSince(work.createdAt)
                                    ))
                                }
                            }
                        }
                    }

                    // Gate 2: Teacher confirmation
                    if let rules, rules.requiresTeacherConfirmation {
                        if !precedingAssignment.isStudentConfirmed(studentID) {
                            reasons.append(.needsTeacherConfirmation(
                                precedingLessonName: preceding.name,
                                assignmentID: precedingAssignment.id ?? UUID()
                            ))
                        }
                    }

                    if reasons.isEmpty {
                        readyStudents.append(makeStatus(
                            student: student, tier: .ready, reasons: [],
                            precedingName: precedingLessonName
                        ))
                    } else {
                        almostReadyStudents.append(makeStatus(
                            student: student, tier: .almostReady, reasons: reasons,
                            precedingName: precedingLessonName
                        ))
                    }
                } else {
                    // Student hasn't been presented preceding lesson
                    // Check if they have the two-before lesson (1 lesson away)
                    let hasTwoBefore = twoBeforeAssignments.contains { la in
                        la.studentIDs.contains(studentID.uuidString)
                    }

                    if hasTwoBefore {
                        // Almost ready — just needs the preceding presentation
                        almostReadyStudents.append(makeStatus(
                            student: student, tier: .almostReady,
                            reasons: [.needsPrecedingPresentation(lessonName: preceding.name)],
                            precedingName: precedingLessonName
                        ))
                    } else {
                        notReadyCount += 1
                    }
                }
            }

            // Only include lessons that have at least one ready or almost-ready student
            if !readyStudents.isEmpty || !almostReadyStudents.isEmpty {
                result.append(LessonGroupCandidate(
                    id: lessonID,
                    lessonName: lesson.name,
                    subject: subject,
                    group: group,
                    orderInGroup: Int(lesson.orderInGroup),
                    readyStudents: readyStudents,
                    almostReadyStudents: almostReadyStudents,
                    notReadyCount: notReadyCount,
                    totalEnrolled: studentIDs.count,
                    precedingLessonName: precedingLessonName
                ))
            }
        }

        candidates = result
    }

    // MARK: - Actions

    func confirmMastery(studentID: UUID, assignmentID: UUID, context: NSManagedObjectContext) {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "id == %@", assignmentID as CVarArg)
        guard let assignment = context.safeFetch(request).first else { return }
        assignment.confirmStudent(studentID)
        context.safeSave()

        // Trigger auto-unlock for the next lesson in sequence
        if let lessonUUID = UUID(uuidString: assignment.lessonID) {
            ReadinessAutoUnlockService.checkAndUnlock(
                afterConfirmationOn: lessonUUID,
                studentID: studentID,
                context: context
            )
        }

        loadData(context: context)
    }

    @discardableResult
    func createPresentation(lessonID: UUID, context: NSManagedObjectContext) -> CDLessonAssignment? {
        guard !selectedStudentIDs.isEmpty else { return nil }
        let draft = PresentationFactory.makeDraft(
            lessonID: lessonID,
            studentIDs: Array(selectedStudentIDs),
            context: context
        )
        context.safeSave()
        selectedStudentIDs.removeAll()
        loadData(context: context)
        return draft
    }

    func toggleStudentSelection(_ studentID: UUID) {
        if selectedStudentIDs.contains(studentID) {
            selectedStudentIDs.remove(studentID)
        } else {
            selectedStudentIDs.insert(studentID)
        }
    }

    func selectAllReady(for candidate: LessonGroupCandidate) {
        for student in candidate.readyStudents {
            selectedStudentIDs.insert(student.id)
        }
    }

    // MARK: - Helpers

    private func makeStatus(
        student: CDStudent,
        tier: ReadinessTier,
        reasons: [GroupBlockingReason],
        precedingName: String?
    ) -> GroupStudentStatus {
        GroupStudentStatus(
            id: student.id ?? UUID(),
            firstName: student.firstName,
            lastName: student.lastName,
            nickname: student.nickname,
            level: student.level,
            tier: tier,
            blockingReasons: reasons,
            precedingLessonName: precedingName
        )
    }

    private func daysSince(_ date: Date?) -> Int {
        guard let date else { return 0 }
        return Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
    }
}
