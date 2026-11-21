// LadderInput.swift
// What the one ladder reads about a child on a lesson, and where the screens
// on the view context get the two parts of it they used to leave out.
//
// Domain logic review 2026-11-20, R14: Three Years counted practice on the
// ladder while the Checklist and the timeline didn't, and the recap's pill
// stored a "Practicing" state no ladder read. Now every screen hands the
// ladder the same input (`ChecklistDisplayStatus.resolve(_:)`), with finished
// practice in it, and the stored Practicing / Ready for Assessment state as a
// floor: the mark never reads lower than what the guide set by hand
// (plan "Domain logic fixes", Decision 7).

import CoreData
import Foundation

/// Everything the ladder reads about one child on one lesson.
nonisolated struct LadderInput: Sendable, Equatable {
    var isMastered = false
    /// Her work on the lesson, open and closed (`WorkOwnership`).
    var workStatuses: [WorkStatus] = []
    /// Finished practices on her work on the lesson (`CDWorkCheckIn.isPractice`).
    var practiceSessions = 0
    /// The furthest state the guide stored by hand on her record of the
    /// lesson, when it is Practicing or Ready for Assessment.
    var storedState: LessonPresentationState?
    var isPresented = false
    var isPlanned = false
    var blockingReason: BlockingReason = .none
}

nonisolated extension ChecklistDisplayStatus {

    /// The one ladder, from the one input. The stored state is a floor:
    /// Practicing reads at least Practicing, Ready for Assessment at least
    /// Reviewing, whatever her work says.
    static func resolve(_ input: LadderInput) -> ChecklistDisplayStatus {
        let rung = resolve(
            isMastered: input.isMastered,
            workStatuses: input.workStatuses,
            practiceSessions: input.practiceSessions,
            isPresented: input.isPresented,
            isPlanned: input.isPlanned,
            blockingReason: input.blockingReason
        )
        guard let floor = input.storedState.flatMap(Self.floor(for:)) else { return rung }
        return max(rung, floor)
    }

    /// The rung a stored state holds the mark at, or nil when it holds none:
    /// Presented is where every given lesson starts, and the mastered state is
    /// a mastery mark, read as one (`SequenceStanding.isMasteryMark`).
    static func floor(for state: LessonPresentationState) -> ChecklistDisplayStatus? {
        switch state {
        case .practicing: .practicing
        case .readyForAssessment: .reviewing
        case .presented, .proficient: nil
        }
    }
}

/// Finished practice and the stored state, by lesson and child, for the
/// screens that read the ladder off the view context (the Checklist, the
/// Children view, the student page's timeline). Three Years reads the same
/// two facts off its background snapshot (`CurriculumMapLoader`).
nonisolated struct LadderEvidence {
    /// lessonID → studentID → finished practices.
    private var practice: [String: [String: Int]] = [:]
    /// lessonID → studentID → the furthest stored state that holds a floor.
    private var stored: [String: [String: LessonPresentationState]] = [:]

    /// Nothing recorded: every count is 0 and no state is stored.
    init() {}

    /// Reads both in two fetches, for `lessonIDs`.
    ///
    /// - Parameter works: every work row on those lessons, when the caller
    ///   already holds them; nil fetches them. Practice is a check-in on one
    ///   child's work, so it counts for the row's owner.
    init(lessonIDs: Set<String>, works: [CDWorkModel]? = nil, in context: NSManagedObjectContext) {
        guard !lessonIDs.isEmpty else { return }
        let rows = works ?? Self.fetchWork(lessonIDs: lessonIDs, in: context)
        var rowByID: [String: CDWorkModel] = [:]
        for row in rows where !row.isDeleted {
            if let id = row.id?.uuidString { rowByID[id] = row }
        }
        for checkIn in CDWorkCheckIn.practice(onWorkIDs: Set(rowByID.keys), in: context) {
            guard let row = rowByID[checkIn.workID.uppercased()] ?? rowByID[checkIn.workID],
                  let owner = UUID(uuidString: row.studentID)?.uuidString else { continue }
            practice[row.lessonID, default: [:]][owner, default: 0] += 1
        }

        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(
            format: "lessonID IN %@ AND stateRaw IN %@", Array(lessonIDs),
            [LessonPresentationState.practicing.rawValue, LessonPresentationState.readyForAssessment.rawValue]
        )
        for row in context.safeFetch(request) where !row.isDeleted {
            let state = row.state
            let known = stored[row.lessonID]?[row.studentID]
            stored[row.lessonID, default: [:]][row.studentID] = Self.further(known, state)
        }
    }

    /// One child's two facts on one lesson.
    nonisolated struct Entry: Sendable, Equatable {
        var practiceSessions = 0
        var storedState: LessonPresentationState?
    }

    func entry(lesson: String, student: String) -> Entry {
        Entry(practiceSessions: practiceSessions(lesson: lesson, student: student),
              storedState: storedState(lesson: lesson, student: student))
    }

    func practiceSessions(lesson: String, student: String) -> Int {
        practice[lesson]?[student] ?? 0
    }

    func storedState(lesson: String, student: String) -> LessonPresentationState? {
        stored[lesson]?[student]
    }

    /// The further of two stored states: Ready for Assessment over Practicing.
    static func further(
        _ lhs: LessonPresentationState?, _ rhs: LessonPresentationState?
    ) -> LessonPresentationState? {
        guard let lhs else { return rhs }
        guard let rhs else { return lhs }
        let lhsRung = ChecklistDisplayStatus.floor(for: lhs) ?? .presented
        let rhsRung = ChecklistDisplayStatus.floor(for: rhs) ?? .presented
        return rhsRung > lhsRung ? rhs : lhs
    }

    private static func fetchWork(lessonIDs: Set<String>, in context: NSManagedObjectContext) -> [CDWorkModel] {
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "lessonID IN %@", Array(lessonIDs))
        return context.safeFetch(request)
    }
}
