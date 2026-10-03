//
//  LessonSequenceOrder.swift
//  Cosmic Daybook
//
//  Where every lesson sits in its sub-area, read once from the library.
//
//  The Groups page asks three things of every lesson it shows (which step of
//  how many, what comes next, what came before) and the sequence ladder asks
//  for one sub-area's lessons in order. Both read this. It is built from the
//  grouping behind `BlockingAlgorithmEngine.buildNextLessonCache`, so "next"
//  here is always the ready queue's "next". It holds plain values, so it is
//  `Sendable` and outlives the context the lessons came from.
//

import CoreData
import Foundation

nonisolated struct LessonSequenceOrder: Sendable, Equatable {

    /// One lesson's place in its sub-area.
    struct Position: Sendable, Hashable {
        let lessonID: String
        let lessonUUID: UUID
        let name: String
        /// Trimmed, as the sub-area's first lesson files it.
        let area: String
        /// Trimmed, as the sub-area's first lesson files it.
        let sequence: String
        /// 1-based: the `k` of "step k of n".
        let step: Int
        /// The `n` of "step k of n".
        let stepCount: Int
        let previousLessonID: String?
        let nextLessonID: String?

        /// "3 of 7".
        var stepLabel: String { "\(step) of \(stepCount)" }
    }

    /// One area + sequence, spelled as filed.
    struct SubArea: Sendable, Hashable {
        let area: String
        let sequence: String
    }

    /// lessonID → its place. A lesson with no area or no sequence has no
    /// sub-area to sit in, and is absent.
    let positions: [String: Position]
    /// Every sub-area in the library, by area then sequence name.
    let subAreas: [SubArea]
    /// Each sub-area's lesson IDs in order, keyed by `Self.key(area:sequence:)`.
    private let lessonIDsBySubArea: [String: [String]]

    init(lessons: [CDLesson]) {
        var positions: [String: Position] = [:]
        var subAreas: [SubArea] = []
        var lessonIDsBySubArea: [String: [String]] = [:]
        for ordered in BlockingAlgorithmEngine.orderedSequenceGroups(lessons) {
            let identified = ordered.compactMap { lesson in lesson.id.map { (lesson, $0) } }
            guard let first = identified.first?.0 else { continue }
            let subArea = SubArea(area: first.area.trimmed(), sequence: first.sequence.trimmed())
            let ids = identified.map { $0.1.uuidString }
            subAreas.append(subArea)
            lessonIDsBySubArea[Self.key(area: subArea.area, sequence: subArea.sequence)] = ids
            for (offset, (lesson, uuid)) in identified.enumerated() where positions[uuid.uuidString] == nil {
                positions[uuid.uuidString] = Position(
                    lessonID: uuid.uuidString,
                    lessonUUID: uuid,
                    name: lesson.name,
                    area: subArea.area,
                    sequence: subArea.sequence,
                    step: offset + 1,
                    stepCount: ids.count,
                    previousLessonID: offset > 0 ? ids[offset - 1] : nil,
                    nextLessonID: offset + 1 < ids.count ? ids[offset + 1] : nil
                )
            }
        }
        self.positions = positions
        self.subAreas = subAreas.sorted { lhs, rhs in
            let byArea = lhs.area.localizedCaseInsensitiveCompare(rhs.area)
            if byArea != .orderedSame { return byArea == .orderedAscending }
            return lhs.sequence.localizedCaseInsensitiveCompare(rhs.sequence) == .orderedAscending
        }
        self.lessonIDsBySubArea = lessonIDsBySubArea
    }

    // MARK: - Questions

    func position(of lessonID: String) -> Position? {
        positions[lessonID]
    }

    /// The sub-area's lessons in order, matched the way the ready queue
    /// matches them (trimmed, case-insensitive). Empty for an unknown one.
    func lessonIDs(area: String, sequence: String) -> [String] {
        lessonIDsBySubArea[Self.key(area: area.trimmed(), sequence: sequence.trimmed())] ?? []
    }

    /// Every area in the library, alphabetically. The guide's saved order is
    /// a view concern (`FilterOrderStore.loadAreaOrder(existing:)`).
    var areas: [String] {
        var seen = Set<String>()
        return subAreas.compactMap { seen.insert($0.area).inserted ? $0.area : nil }
    }

    /// The area's sequences, alphabetically (case-insensitive area match). The
    /// guide's saved order is a view concern
    /// (`FilterOrderStore.loadSequenceOrder(for:existing:)`).
    func sequences(inArea area: String) -> [String] {
        let wanted = area.trimmed()
        return subAreas
            .filter { $0.area.caseInsensitiveCompare(wanted) == .orderedSame }
            .map(\.sequence)
    }

    private static func key(area: String, sequence: String) -> String {
        BlockingAlgorithmEngine.sequenceGroupKey(area: area, sequence: sequence)
    }
}
