//
//  StudentEntity+CoreData.swift
//  Cosmic Daybook
//
//  Building a `StudentEntity` from a managed student. Shared with Daybook
//  Assistant, which compiles this file by path.
//

import CoreData

extension StudentEntity {
    /// Builds an entity snapshot from a managed student. Must be called on the
    /// main actor because it reads `CDStudent` properties off the view context.
    @MainActor
    init?(student: CDStudent) {
        guard let id = student.id else { return nil }
        self.init(
            id: id,
            firstName: student.firstName,
            lastName: student.lastName,
            nickname: student.nickname
        )
    }

    var matcherCandidate: StudentNameMatcher.Candidate {
        StudentNameMatcher.Candidate(id: id, firstName: firstName, lastName: lastName, nickname: nickname)
    }
}
