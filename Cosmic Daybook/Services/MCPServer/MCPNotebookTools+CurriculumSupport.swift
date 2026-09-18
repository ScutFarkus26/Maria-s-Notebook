//
//  MCPNotebookTools+CurriculumSupport.swift
//  Cosmic Daybook
//
//  What the curriculum-editing tools share: how an area or sub-area name is
//  matched, how a sub-area is read back in order, and how an edit is settled
//  into the two ordering columns the Lessons screens read.
//
//  `orderInSequence` is the truth within a sub-area (the `sequence` column):
//  every sequence-level view, the recall engine, the year plan and the track
//  steps sort on it. `sortIndex` is derived — an area-wide index the area
//  view sorts on, rebuilt by walking the area's sub-areas in the map's saved
//  order and numbering every lesson. LessonsRootViewReordering renumbers the
//  first and rebuilds the second after every in-app move, and these helpers
//  do exactly that so a tool edit is indistinguishable from a drag.
//

import CoreData
import Foundation
import OSLog

extension MCPNotebookTools {

    // MARK: - Filing Names

    /// Area and sub-area names compare the way the Lessons screens compare
    /// them: trimmed and case-insensitive. "Math " is "math".
    static func sameFiling(_ lhs: String, _ rhs: String) -> Bool {
        let left: String = lhs.trimmed()
        let right: String = rhs.trimmed()
        return left.caseInsensitiveCompare(right) == ComparisonResult.orderedSame
    }

    /// Lesson names compare diacritic- and case-insensitively, matching
    /// `find_lessons`, so "Rôle" and "role" are one lesson for idempotency.
    static func foldedLessonName(_ name: String) -> String {
        name.folding(options: .diacriticInsensitive, locale: .current).trimmed().lowercased()
    }

    static func allCurriculumLessons(in modelContext: NSManagedObjectContext) -> [CDLesson] {
        modelContext.safeFetch(CDFetchRequest(CDLesson.self))
    }

    /// The top-level areas, in the order the scope map shows them.
    static func curriculumAreas(from lessons: [CDLesson]) -> [String] {
        LessonsViewModel().areas(from: lessons)
    }

    /// Resolves an area argument to the spelling already in the curriculum.
    /// Areas are never created by a tool — a typo here would fork the whole
    /// map — so a miss lists what exists instead.
    static func resolveArea(_ name: String, from lessons: [CDLesson]) throws -> String {
        let areas = curriculumAreas(from: lessons)
        if let match = areas.first(where: { sameFiling($0, name) }) { return match }
        let listing: String = areas.isEmpty
            ? "The curriculum has no areas yet."
            : "Existing areas: \(areas.joined(separator: ", "))."
        throw MCPToolError(
            "No area named \"\(name)\" is in the curriculum, and tools never create a new "
                + "top-level area. \(listing) Ask the guide which one this belongs under."
        )
    }

    /// The area's sub-areas in the map's saved order, plus "Ungrouped" last
    /// when any lesson is filed without one — the same list the map reorders.
    static func orderedSequences(inArea area: String, from lessons: [CDLesson]) -> [String] {
        var sequences = LessonsViewModel().groups(for: area, lessons: lessons)
        let hasUngrouped = lessons.contains { sameFiling($0.area, area) && $0.sequence.trimmed().isEmpty }
        if hasUngrouped { sequences.append(ungroupedSequenceLabel) }
        return sequences
    }

    static let ungroupedSequenceLabel = "Ungrouped"

    /// The sub-area's spelling as it already exists under the area, if any.
    static func existingSequence(named name: String, inArea area: String, from lessons: [CDLesson]) -> String? {
        LessonsViewModel().groups(for: area, lessons: lessons).first { sameFiling($0, name) }
    }

    static func resolveSequence(_ name: String, inArea area: String, from lessons: [CDLesson]) throws -> String {
        if let match = existingSequence(named: name, inArea: area, from: lessons) { return match }
        let sequences = LessonsViewModel().groups(for: area, lessons: lessons)
        let listing = sequences.isEmpty
            ? "\(area) has no sub-areas yet."
            : "Sub-areas of \(area): \(sequences.joined(separator: ", "))."
        throw MCPToolError("No sub-area named \"\(name)\" under \(area). \(listing)")
    }

    // MARK: - Reading a Sub-Area

    /// The lessons filed under one sub-area in their taught order — the sort
    /// every sequence-level screen uses. Pass `ungroupedSequenceLabel` for
    /// lessons filed with no sub-area.
    static func lessonsInSequence(
        _ sequence: String, area: String, from lessons: [CDLesson]
    ) -> [CDLesson] {
        lessons.filter { lesson in
            guard sameFiling(lesson.area, area) else { return false }
            if sequence == ungroupedSequenceLabel { return lesson.sequence.trimmed().isEmpty }
            return sameFiling(lesson.sequence, sequence)
        }
        .sorted { lhs, rhs in
            if lhs.orderInSequence != rhs.orderInSequence { return lhs.orderInSequence < rhs.orderInSequence }
            return LessonsViewModel.lessonNameOrder(lhs, rhs)
        }
    }

    // MARK: - Settling an Edit

    /// Numbers a sub-area 0…n in the given order, the way every in-app move
    /// does (`moveLessonsInArea`, `insertLessonAfter`).
    static func renumberSequence(_ ordered: [CDLesson]) {
        for (index, lesson) in ordered.enumerated() where lesson.orderInSequence != Int64(index) {
            lesson.orderInSequence = Int64(index)
        }
    }

    /// Mirrors `LessonsRootView.rebuildSortIndexForArea`: walks the area's
    /// sub-areas in the map's order and numbers every lesson, so the area
    /// view and the pickers that sort on `sortIndex` agree with the sub-areas.
    static func rebuildSortIndex(forArea area: String, from lessons: [CDLesson]) {
        var position: Int64 = 0
        for sequence in orderedSequences(inArea: area, from: lessons) {
            for lesson in lessonsInSequence(sequence, area: area, from: lessons) {
                if lesson.sortIndex != position { lesson.sortIndex = position }
                position += 1
            }
        }
    }

    /// The best-effort track refresh AddLessonView and the bulk sheet make
    /// after adding a lesson: keeps the sub-area's `CDTrackEntity` steps in
    /// step with its lessons. Failures are logged, never surfaced — the lesson
    /// is already saved, and the service defers itself until a CKShare exists.
    static func refreshSequenceTrack(area: String, sequence: String, in modelContext: NSManagedObjectContext) {
        let trimmedArea = area.trimmed()
        let trimmedSequence = sequence.trimmed()
        guard !trimmedArea.isEmpty, !trimmedSequence.isEmpty,
              SequenceTrackService.isTrack(area: trimmedArea, sequence: trimmedSequence, context: modelContext)
        else { return }
        do {
            _ = try SequenceTrackService.getOrCreateTrack(
                area: trimmedArea, sequence: trimmedSequence, context: modelContext
            )
            _ = modelContext.safeSave()
        } catch {
            Logger.lessons.warning(
                "MCP could not refresh the track for \(trimmedArea)/\(trimmedSequence): \(error)"
            )
        }
    }

    // MARK: - Output

    /// One numbered line per lesson, positions 1-based, in the same
    /// `[lesson id=<uuid>]` shape `find_lessons` prints.
    static func numberedLessonLines(_ lessons: [CDLesson]) -> String {
        lessons.enumerated()
            .map { "\($0.offset + 1). \(describeLesson($0.element))" }
            .joined(separator: "\n")
    }

    static func filingLabel(area: String, sequence: String) -> String {
        sequence.trimmed().isEmpty ? "\(area) › \(ungroupedSequenceLabel)" : "\(area) › \(sequence)"
    }
}
