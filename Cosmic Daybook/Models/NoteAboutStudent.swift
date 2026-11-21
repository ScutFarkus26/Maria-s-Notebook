// NoteAboutStudent.swift
// The one answer to "is this note about her?" (domain logic review
// 2026-11-20, R9). It was written six ways, and one of them (the Progress
// tab's sequence notes) found a note only through its student links, which
// exist only for notes about two or more children, so a lesson note about
// one child never counted in her sequence card.

import CoreData
import Foundation

/// Which notes beside her own count as about her. Her own notes (scoped to
/// her alone) and group notes that name her always do.
nonisolated struct NoteAudience: Sendable, Equatable {
    /// Whole-class notes count too ("The class planted bulbs").
    var includesWholeClass: Bool
    /// And whole-class context notes: a community meeting's lines and a
    /// calendar day's note (`CDNote.isContextNote`). They are about the
    /// class's day, not any one child, and used to land on every child's
    /// Notes tab and feed Writing Help.
    var includesContext: Bool

    /// Her notes and the group notes naming her: insights, "last observed",
    /// her sequence cards.
    static let herOwn = NoteAudience(includesWholeClass: false, includesContext: false)
    /// Those and the class's notes, context aside: her Notes tab, her reports,
    /// the sequence recap.
    static let withClass = NoteAudience(includesWholeClass: true, includesContext: false)
    /// Every note whose scope includes her, context notes too: notes already
    /// found through something of hers (her work, her presentation).
    static let everything = NoteAudience(includesWholeClass: true, includesContext: true)
}

nonisolated extension CDNote {

    /// A whole-class note about the class's day rather than a child: a
    /// community meeting's line or a calendar day's note.
    var isContextNote: Bool {
        scopeIsAll && (communityTopicID != nil || schoolDayOverrideID != nil)
    }

    /// The marker a note the app writes itself carries in `reportedBy` (the
    /// school-year rollover's "Promoted from Lower to Upper…"). Such a note
    /// isn't an observation, so it doesn't count as "last observed"
    /// (domain logic review A11).
    static let appReporter = "app"

    /// Whether the app wrote this note itself (`appReporter`).
    var isAppWritten: Bool { reportedBy == Self.appReporter }

    /// The notes that may be about her, as a fetch predicate: those indexed to
    /// her, every group note (the children a group note names are in its
    /// scope blob, which a fetch can't read), and the class's notes when
    /// `audience` takes them. Narrow the result with `isAbout(_:_:)`.
    static func aboutPredicate(_ studentID: UUID, _ audience: NoteAudience) -> NSPredicate {
        var candidates = [
            NSPredicate(format: "searchIndexStudentID == %@", studentID as CVarArg),
            NSPredicate(format: "scopeIsAll == NO AND searchIndexStudentID == nil")
        ]
        if audience.includesWholeClass {
            candidates.append(audience.includesContext
                ? NSPredicate(format: "scopeIsAll == YES")
                : NSPredicate(
                    format: "scopeIsAll == YES AND communityTopicID == nil AND schoolDayOverrideID == nil"
                ))
        }
        return NSCompoundPredicate(orPredicateWithSubpredicates: candidates)
    }

    /// Whether the note is about her for `audience`. The note's scope decides,
    /// not its student links: a link left behind by an older re-scope doesn't
    /// make a note hers, and a group note whose links are missing still is.
    func isAbout(_ studentID: UUID, _ audience: NoteAudience) -> Bool {
        if searchIndexStudentID == studentID { return true }
        switch scope {
        case .student(let id):
            return id == studentID
        case .students(let ids):
            return ids.contains(studentID)
        case .all:
            return audience.includesWholeClass && (audience.includesContext || !isContextNote)
        }
    }
}
