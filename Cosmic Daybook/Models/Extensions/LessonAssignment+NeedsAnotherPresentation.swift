//
//  LessonAssignment+NeedsAnotherPresentation.swift
//  Cosmic Daybook
//
//  "Needs another presentation for this child." Kept in its own file: an
//  extension has no dependency fingerprint (CLAUDE.md, Build-setting rules).
//

import Foundation

nonisolated extension CDLessonAssignment {
    /// Whether this presentation needs giving to `studentID` again: the shared
    /// flag (everyone on it), or her own follow-up row says re-present. Ask
    /// this, not `needsAnotherPresentation`, when the reader is about one child.
    func needsAnotherPresentation(for studentID: String, given representations: ChildRepresentations) -> Bool {
        if needsAnotherPresentation { return true }
        guard let id else { return false }
        return representations.contains(presentationID: id.uuidString, studentID: studentID)
    }
}
