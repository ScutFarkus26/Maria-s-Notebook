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
import OSLog

/// One row of the Bulk Entry grid, trimmed.
struct BulkLessonDraft {
    let name: String
    let area: String
    let sequence: String
    let section: String
    let writeUp: String
}

enum BulkLessonInsertion {
    private static let logger = Logger.lessons

    struct Outcome {
        var inserted: [CDLesson] = []
        /// Names refused because the same name was already in that sub-area.
        var skipped: [String] = []
    }

    /// The key a sub-area's numbering is kept under: area and sequence trimmed
    /// and lowercased, so "Math " and "math" are one sequence, as the Lessons
    /// screen shows them. Raw keys numbered new lessons from 0 whenever the
    /// stored spelling differed from the typed one.
    nonisolated static func orderKey(area: String, sequence: String) -> String {
        "\(area.trimmed().lowercased())|\(sequence.trimmed().lowercased())"
    }

    /// The highest `orderInSequence` on file in each sub-area, by `orderKey`.
    static func maxOrders(of lessons: [CDLesson]) -> [String: Int] {
        var result: [String: Int] = [:]
        for lesson in lessons where !lesson.isDeleted {
            let key = orderKey(area: lesson.area, sequence: lesson.sequence)
            result[key] = max(result[key] ?? -1, Int(lesson.orderInSequence))
        }
        return result
    }

    /// The Bulk Entry sheet's Save: inserts the drafts after the lessons on
    /// file in each sub-area, with the tracks their sub-areas take, and saves
    /// them in one save. Nil when the save failed, and then nothing from the
    /// grid stays in the context: left there, the retry found each lesson's
    /// own unsaved copy and called every row already filed (bug hunt
    /// 2026-10-12, #4). Other screens' unsaved edits are left alone, and the
    /// caller shows its own message.
    static func insertAndSave(
        _ drafts: [BulkLessonDraft],
        using repository: LessonRepository,
        source: LessonSource,
        personalKind: PersonalLessonKind?,
        saveCoordinator: SaveCoordinator
    ) -> Outcome? {
        let context = repository.context
        let transaction = ContextMutationTransaction(context: context)
        let outcome = insert(
            drafts, using: repository, source: source, personalKind: personalKind,
            maxOrderBySequence: maxOrders(of: repository.fetchLessons())
        )
        guard !outcome.inserted.isEmpty else {
            transaction.commit()
            return outcome
        }
        addTracks(for: outcome.inserted, in: context)
        guard saveCoordinator.save(context, reason: "Add lessons", alertOnFailure: false) else {
            transaction.rollback()
            return nil
        }
        transaction.commit()
        return outcome
    }

    /// Creates or updates the track for each new lesson's sub-area that is a
    /// track (`SequenceTrackService`), once per sub-area.
    private static func addTracks(for lessons: [CDLesson], in context: NSManagedObjectContext) {
        var processedSequences: Set<String> = []
        for lesson in lessons {
            let area = lesson.area.trimmed()
            let sequence = lesson.sequence.trimmed()
            guard !area.isEmpty, !sequence.isEmpty,
                  processedSequences.insert("\(area)|\(sequence)").inserted,
                  SequenceTrackService.isTrack(area: area, sequence: sequence, context: context)
            else { continue }
            do {
                _ = try SequenceTrackService.getOrCreateTrack(area: area, sequence: sequence, context: context)
            } catch {
                logger.warning("Failed to create/update CDTrackEntity for \(area)/\(sequence): \(error)")
            }
        }
    }

    /// Creates a lesson per draft through `repository`, numbering each after
    /// the last lesson in its sub-area. `maxOrderBySequence` is keyed by
    /// `orderKey` and holds the highest `orderInSequence` on file.
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
            let sequenceKey = orderKey(area: draft.area, sequence: draft.sequence)
            let nextOrder = (maxOrder[sequenceKey] ?? -1) + 1
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
                maxOrder[sequenceKey] = nextOrder
                outcome.inserted.append(lesson)
            } catch {
                outcome.skipped.append(draft.name)
            }
        }
        return outcome
    }
}
