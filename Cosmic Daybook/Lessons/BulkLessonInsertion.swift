//
//  BulkLessonInsertion.swift
//  Cosmic Daybook
//
//  The insertion step of the Bulk Entry sheet, kept apart from the view so
//  the one rule it enforces is easy to see: a name already filed in the
//  same sub-area — in the store, or higher up in the same grid — is skipped
//  and reported, never inserted twice. Geometry › Area was entered twice
//  through this sheet on Danny's store and every child's year plan doubled.
//

import CoreData
import Foundation

/// One row of the Bulk Entry grid, trimmed.
struct BulkLessonDraft {
    let name: String
    let area: String
    let sequence: String
    let section: String
    let writeUp: String
}

enum BulkLessonInsertion {
    struct Outcome {
        var inserted: [CDLesson] = []
        /// Names refused because the same name was already in that sub-area.
        var skipped: [String] = []
    }

    /// Creates a lesson per draft through `repository`, numbering each after
    /// the last lesson in its sub-area. `maxOrderBySequence` is keyed
    /// `"area|sequence"` and holds the highest `orderInSequence` on file.
    static func insert(
        _ drafts: [BulkLessonDraft],
        using repository: LessonRepository,
        source: LessonSource,
        personalKind: PersonalLessonKind?,
        maxOrderBySequence: [String: Int]
    ) -> Outcome {
        var outcome = Outcome()
        var maxOrder = maxOrderBySequence
        var namesInBatch: Set<String> = []
        for draft in drafts {
            let nameKey = LessonRepository.nameKey(name: draft.name, area: draft.area, sequence: draft.sequence)
            guard namesInBatch.insert(nameKey).inserted else {
                outcome.skipped.append(draft.name)
                continue
            }
            let orderKey = "\(draft.area)|\(draft.sequence)"
            let nextOrder = (maxOrder[orderKey] ?? -1) + 1
            do {
                let lesson = try repository.createLesson(
                    name: draft.name,
                    area: draft.area,
                    sequence: draft.sequence,
                    section: draft.section,
                    writeUp: draft.writeUp,
                    orderInSequence: nextOrder,
                    source: source,
                    personalKind: personalKind
                )
                maxOrder[orderKey] = nextOrder
                outcome.inserted.append(lesson)
            } catch {
                outcome.skipped.append(draft.name)
            }
        }
        return outcome
    }
}
