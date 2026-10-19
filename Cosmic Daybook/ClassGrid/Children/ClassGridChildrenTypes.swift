// ClassGridChildrenTypes.swift
// Value types for the Class Grid's Children view (once the Progress Dashboard).
//
// Hierarchy: Student → Subject (lesson.area) → Sequence (lesson.sequence) → Lesson pills.
// Each pill carries the Class Grid's one status (`ChecklistDisplayStatus`), drawn as the
// Checklist's mark, so a strip reads the same as the Checklist's row.

import Foundation

/// One student's full progression map across every subject they've started.
struct StudentProgressionCard: Identifiable {
    let id: UUID  // studentID
    let firstName: String
    let lastName: String
    let nickname: String?
    let level: CDStudent.Level
    /// Her year in class (1 in her first school year), when her start date is on file.
    var yearInClass: Int?
    let subjects: [SubjectProgression]

    var fullName: String { "\(firstName) \(lastName)" }

    var initials: String { "\(firstName.prefix(1))\(lastName.prefix(1))" }

    /// Total number of (subject, sequence) threads visible for this student.
    var sequenceCount: Int { subjects.reduce(0) { $0 + $1.sequences.count } }

    /// Lessons with a mastery mark across her started sequences.
    var masteredCount: Int {
        subjects.reduce(0) { total, subject in
            total + subject.sequences.reduce(0) { $0 + $1.pills.filter { $0.status == .mastered }.count }
        }
    }

    /// "Upper · Year 2 · 3 areas".
    var subtitle: String {
        var parts = [level.rawValue]
        if let yearInClass { parts.append(CurriculumTimeline.yearBadge(yearInClass)) }
        parts.append("\(subjects.count) area\(subjects.count == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
    }

    /// "31 lessons mastered".
    var masteredText: String {
        "\(masteredCount) lesson\(masteredCount == 1 ? "" : "s") mastered"
    }

    /// The card with only the areas `keep` passes.
    func keepingSubjects(where keep: (SubjectProgression) -> Bool) -> StudentProgressionCard {
        StudentProgressionCard(
            id: id, firstName: firstName, lastName: lastName, nickname: nickname, level: level,
            yearInClass: yearInClass, subjects: subjects.filter(keep)
        )
    }
}

/// A subject (lesson.area) that a student has started, grouping all their active sequences inside it.
struct SubjectProgression: Identifiable {
    let id: String  // "\(studentID)|\(area)"
    let area: String
    let sequences: [SequenceProgression]
}

/// A sequence (lesson.sequence) that a student has started, with the ordered list of lesson pills.
struct SequenceProgression: Identifiable {
    let id: String  // "\(studentID)|\(area)|\(sequence)"
    let studentID: UUID
    let area: String
    let sequence: String
    let pills: [LessonPillState]

    var presentedCount: Int {
        pills.filter { $0.isPresentedOrBeyond }.count
    }

    var totalCount: Int { pills.count }
}

/// One lesson as a mark in a student's sequence strip.
struct LessonPillState: Identifiable {
    let id: UUID  // lessonID
    let lessonID: UUID
    let name: String
    let status: ChecklistDisplayStatus
    let orderInSequence: Int

    /// True once the lesson has been presented (presented / practicing / reviewing / mastered).
    var isPresentedOrBeyond: Bool { status >= .presented }
}

extension ChecklistDisplayStatus {
    /// A student-page status as the Class Grid draws it. Not started is Not yet (the
    /// Children view reads no readiness), planned or scheduled is Planned.
    init(_ node: LessonNodeStatus) {
        switch node {
        case .notStarted: self = .notReady
        case .scheduled: self = .planned
        case .presented: self = .presented
        case .practicing: self = .practicing
        case .reviewing: self = .reviewing
        case .mastered: self = .mastered
        }
    }
}
