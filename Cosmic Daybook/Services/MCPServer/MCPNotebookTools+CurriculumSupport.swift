//
//  MCPNotebookTools+CurriculumSupport.swift
//  Cosmic Daybook
//
//  What the curriculum-editing tools share: how an area or sub-area name is
//  matched, how a sub-area is read back in order, and how an edit is settled
//  into the two ordering columns the Lessons screens read.
//
//  `orderInSequence` is the truth within a sub-area (the `sequence` column):
//  every sequence-level view, the recall engine and the year plan sort on
//  it. `sortIndex` is derived — an area-wide index the area view sorts on,
//  rebuilt by walking the area's sub-areas in the map's saved order and
//  numbering every lesson. LessonsRootViewReordering renumbers the
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

    /// The area's sub-areas in the map's saved order (`LessonRepository`).
    static func orderedSequences(inArea area: String, from lessons: [CDLesson]) -> [String] {
        LessonRepository.orderedSequences(inArea: area, from: lessons)
    }

    static let ungroupedSequenceLabel = SubAreaOrder.ungroupedName

    static func isUngroupedLabel(_ name: String) -> Bool {
        sameFiling(name, ungroupedSequenceLabel)
    }

    /// The `sequence` a sub-area argument stores: "Ungrouped", the label the
    /// reads print for lessons filed without one, means no sub-area. Taken
    /// literally it made a real sub-area the reads then hid (#26).
    static func storedSequence(forArgument name: String) -> String {
        isUngroupedLabel(name) ? "" : name
    }

    /// The sub-area's spelling as it already exists under the area, if any.
    static func existingSequence(named name: String, inArea area: String, from lessons: [CDLesson]) -> String? {
        LessonsViewModel().groups(for: area, lessons: lessons).first { sameFiling($0, name) }
    }

    static func resolveSequence(_ name: String, inArea area: String, from lessons: [CDLesson]) throws -> String {
        if isUngroupedLabel(name), orderedSequences(inArea: area, from: lessons).contains(ungroupedSequenceLabel) {
            return ungroupedSequenceLabel
        }
        if let match = existingSequence(named: name, inArea: area, from: lessons) { return match }
        let sequences = LessonsViewModel().groups(for: area, lessons: lessons)
        let listing = sequences.isEmpty
            ? "\(area) has no sub-areas yet."
            : "Sub-areas of \(area): \(sequences.joined(separator: ", "))."
        throw MCPToolError("No sub-area named \"\(name)\" under \(area). \(listing)")
    }

    // MARK: - Reading a Sub-Area

    /// The lessons filed under one sub-area in the one lesson order
    /// (`LessonRepository.lessonsInSequence`).
    static func lessonsInSequence(
        _ sequence: String, area: String, from lessons: [CDLesson]
    ) -> [CDLesson] {
        LessonRepository.lessonsInSequence(sequence, area: area, from: lessons)
    }

    // MARK: - Settling an Edit

    /// Numbers a sub-area 0…n in the given order, the way every in-app move
    /// does (`moveLessonsInArea`, `insertLessonAfter`).
    static func renumberSequence(_ ordered: [CDLesson]) {
        LessonOrder.renumber(ordered)
    }

    /// The area's `sortIndex` rebuilt as an in-app move rebuilds it
    /// (`LessonRepository.rebuildSortIndex`).
    static func rebuildSortIndex(forArea area: String, from lessons: [CDLesson]) {
        LessonRepository.rebuildSortIndex(forArea: area, from: lessons)
    }

    // MARK: - Output

    /// One numbered line per lesson, positions 1-based, in the same
    /// `[lesson id=<uuid>]` shape `find_lessons` prints.
    /// `files` adds each lesson's own files (`find_lessons` only;
    /// receipts list lessons without them).
    static func numberedLessonLines(_ lessons: [CDLesson], files: LessonFileTitles? = nil) -> String {
        lessons.enumerated()
            .map { "\($0.offset + 1). \(describeLesson($0.element))\(files?.suffix(for: $0.element) ?? "")" }
            .joined(separator: "\n")
    }

    static func filingLabel(area: String, sequence: String) -> String {
        sequence.trimmed().isEmpty ? "\(area) › \(ungroupedSequenceLabel)" : "\(area) › \(sequence)"
    }
}
