// CurriculumMapTypes.swift
// Value types for the Three-Year View: one computed layer over the records the
// notebook already keeps, answering "where is this child across the whole
// plane?" rather than "where is she on one track?".
//
// Nothing here is stored. CurriculumMapLoader reduces CD* records to these
// Sendable refs on a background context, ClassGridEngine derives a
// CurriculumCell per (child, lesson) from them, and both screens and the MCP
// tools read the same cells — so "presented but never chosen" means one thing
// everywhere. Everything is `nonisolated` so the maths can leave the main actor.

import Foundation

// MARK: - Cell State
//
// A cell's rung is the Class Grid's one status, `ChecklistDisplayStatus`
// (Not yet, Presented, Practicing, Reviewing, Mastered here; Ready and Planned
// are the Checklist's, which reads plans and readiness). The old map's own
// ladder (not presented, presented, chosen, repeated, mastered) is gone; the
// Claude tools keep its words (`MCPNotebookTools+CurriculumMap`).

/// How many rows a grid shows: whole areas, the milestones inside them, or
/// every lesson in the catalog.
nonisolated enum CurriculumGranularity: String, CaseIterable, Sendable, Identifiable {
    case area
    case keyLessons = "keyLesson"
    case allLessons

    var id: String { rawValue }

    var label: String {
        switch self {
        case .area: "Areas"
        case .keyLessons: "Key lessons"
        case .allLessons: "All lessons"
        }
    }
}

// MARK: - Inputs

/// A curriculum lesson reduced to what the map needs. `area` and `sequence`
/// arrive trimmed so grouping matches the Progress Dashboard's.
nonisolated struct CurriculumLessonRef: Sendable, Hashable, Identifiable {
    let id: UUID
    let name: String
    let area: String
    let sequence: String
    let section: String
    let orderInSequence: Int
    let sortIndex: Int
    /// `CDLesson.greatLessonRaw` — a `GreatLesson` raw value, resolved by the views.
    let greatLessonRaw: String?
    let isStory: Bool
    let isKeyLesson: Bool
}

nonisolated struct CurriculumStudentRef: Sendable, Hashable, Identifiable {
    let id: UUID
    let firstName: String
    let lastName: String
    let nickname: String?
    let levelRaw: String
    let dateStarted: Date?
    let isEnrolled: Bool

    var fullName: String { "\(firstName) \(lastName)" }
}

/// A presentation that was given (`CDLessonAssignment`, state presented).
/// `presentedAt` is nil for bulk "previously presented" marks.
nonisolated struct CurriculumPresentationRef: Sendable, Hashable, Identifiable {
    let id: UUID
    let lessonID: UUID
    let studentIDs: [UUID]
    let presentedAt: Date?
    /// Children the guide confirmed proficient on this presentation.
    let confirmedStudentIDs: [UUID]
}

/// The per-child mastery record (`CDLessonPresentation`).
nonisolated struct CurriculumMasteryRef: Sendable, Hashable, Identifiable {
    let id: UUID
    let studentID: UUID
    let lessonID: UUID
    let isMastered: Bool
    let presentedAt: Date?
    let masteredAt: Date?
    let lastObservedAt: Date?
}

/// A work item (`CDWorkModel`) with everyone on it — owner and participants.
nonisolated struct CurriculumWorkRef: Sendable, Hashable, Identifiable {
    let id: UUID
    let lessonID: UUID
    let studentIDs: [UUID]
    let statusRaw: String
    let assignedAt: Date?
    let completedAt: Date?
    let lastTouchedAt: Date?
    /// The child the row belongs to (`CDWorkModel.studentID`), when it names
    /// one. Linked copies each list the whole group in `studentIDs`, so only
    /// this tells a child's own copy from a classmate's.
    var ownerID: UUID?
    /// One row carrying several children by construction (project-session
    /// work), never one of a set of linked copies: it counts for everyone on
    /// it. `WorkGrouping.areLinkedCopies`' rule.
    var isSharedRow = false

    var isBeyondActive: Bool { status != .active }

    /// The row's status, read the way `CDWorkModel.status` reads it.
    var status: WorkStatus { WorkStatus(rawValue: statusRaw) ?? .active }
}

nonisolated struct CurriculumPracticeRef: Sendable, Hashable, Identifiable {
    let id: UUID
    let date: Date?
    let studentIDs: [UUID]
    let workIDs: [UUID]
}

nonisolated struct CurriculumRecallRef: Sendable, Hashable, Identifiable {
    let id: UUID
    let studentID: UUID
    let lessonID: UUID
    let outcome: RecallOutcome
    let checkedAt: Date?
}

/// Everything the engine needs, loaded once and shared by every screen.
nonisolated struct CurriculumMapInput: Sendable {
    var lessons: [CurriculumLessonRef] = []
    var students: [CurriculumStudentRef] = []
    var presentations: [CurriculumPresentationRef] = []
    var masteries: [CurriculumMasteryRef] = []
    var work: [CurriculumWorkRef] = []
    var practice: [CurriculumPracticeRef] = []
    var recalls: [CurriculumRecallRef] = []
}

// MARK: - Outputs

/// The record ids behind a cell, so a tap can open exactly what the glyph
/// summarises.
nonisolated struct CurriculumEvidence: Sendable, Hashable {
    var presentationIDs: [UUID] = []
    var masteryRecordIDs: [UUID] = []
    var workIDs: [UUID] = []
    var practiceSessionIDs: [UUID] = []
    var recallCheckIDs: [UUID] = []
}

/// One dated record, placed on the time axis. `state` is what the record
/// evidences on its own — a third practice session evidences Reviewing, the
/// first Practicing — so a time bucket can show the best thing that happened
/// in it. Recall checks carry an outcome instead of a state.
nonisolated struct CurriculumEvent: Sendable, Hashable {
    enum Kind: String, Sendable {
        case presentation
        case work
        case practice
        case mastery
        case recall
    }

    let date: Date
    let kind: Kind
    let state: ChecklistDisplayStatus?
    let recall: RecallOutcome?
    let recordID: UUID
}

/// The state of one lesson for one child, with everything it was derived from.
nonisolated struct CurriculumCell: Sendable, Hashable, Identifiable {
    let studentID: UUID
    let lessonID: UUID
    var state: ChecklistDisplayStatus = .notReady
    /// The guide confirmed her ready for the next lesson on a presentation.
    /// Evidence beside the ladder, never a rung of it.
    var isConfirmed: Bool = false
    /// Latest recall-check outcome, if the lesson was ever re-checked.
    var recall: RecallOutcome?
    var firstPresented: Date?
    var lastPresented: Date?
    /// Most recent presentation, work event, practice session, mastery mark, or recall check.
    var lastActivity: Date?
    var practiceCount: Int = 0
    var evidence = CurriculumEvidence()
    var events: [CurriculumEvent] = []

    var id: String { "\(studentID.uuidString)|\(lessonID.uuidString)" }

    init(studentID: UUID, lessonID: UUID) {
        self.studentID = studentID
        self.lessonID = lessonID
    }

    /// The spec's "presented, never chosen": the guide gave it, the child never
    /// picked it up (no work, no practice).
    var isPresentedNeverChosen: Bool { state == .presented }
}

/// A row's worth of cells folded together — an area, a sequence, or a Great
/// Lesson's story lessons — for the collapsed rows and the untouched flag.
nonisolated struct CurriculumAggregate: Sendable, Hashable {
    var state: ChecklistDisplayStatus = .notReady
    var recall: RecallOutcome?
    var firstPresented: Date?
    var lastPresented: Date?
    var lastActivity: Date?
    var lessonCount: Int = 0
    var presentedCount: Int = 0
    var events: [CurriculumEvent] = []

    static let empty = CurriculumAggregate()
}
