// ClassCurriculumMapModel.swift
// The class version of the Three-Year View: lessons (or areas) down the side,
// children across the top sorted by enrollment year so the cohorts read as
// bands, and each child's state on each row. This is the screen for "who has
// not had the distributive law yet" — the answer is a set of names.

import Foundation
import SwiftUI

struct ClassColumn: Identifiable, Hashable {
    let student: CurriculumStudentRef
    let year: Int
    var id: UUID { student.id }
    var badge: String { CurriculumTimeline.yearBadge(year) }
    var shortName: String {
        StudentFormatter.displayName(firstName: student.firstName, lastName: student.lastName)
    }
}

struct ClassRow: Identifiable, Hashable {
    enum Kind: Hashable {
        case greatLessonsHeader
        case greatLesson(String)
        case area(String)
        case sequence(area: String, sequence: String)
        case lesson(UUID)

        var rowID: String {
            switch self {
            case .greatLessonsHeader: "great-lessons"
            case .greatLesson(let raw): "great-\(raw)"
            case .area(let area): "area-\(CurriculumMapEngine.filingKey(area))"
            case .sequence(let area, let sequence):
                "seq-\(CurriculumMapEngine.sequenceKey(area: area, sequence: sequence))"
            case .lesson(let id): "lesson-\(id.uuidString)"
            }
        }

        var depth: Int {
            switch self {
            case .greatLessonsHeader, .area, .sequence: 0
            case .greatLesson, .lesson: 1
            }
        }
    }

    let kind: Kind
    let title: String
    let subtitle: String?
    let tint: Color
    let lessonIDs: [UUID]
    /// Child → glyph. A missing child is not presented.
    let cells: [UUID: CurriculumGlyphSpec]
    let counts: [CurriculumCellState: Int]

    var id: String { kind.rowID }

    var lessonID: UUID? {
        if case .lesson(let id) = kind { return id }
        return nil
    }

    var depth: Int { kind.depth }

    func state(for studentID: UUID) -> CurriculumCellState {
        cells[studentID]?.state ?? .notPresented
    }
}

@Observable
final class ClassCurriculumMapModel {
    private(set) var columns: [ClassColumn] = []
    private(set) var rows: [ClassRow] = []
    private(set) var areas: [String] = []
    private(set) var sequences: [String] = []

    // MARK: - Build

    func rebuild(
        store: CurriculumMapStore,
        area: String?,
        sequence: String?,
        granularity: CurriculumGranularity,
        stateFilter: CurriculumCellState?,
        today: Date = Date(),
        calendar: Calendar = AppCalendar.shared
    ) {
        guard let input = store.input else {
            columns = []
            rows = []
            return
        }
        let all = store.cellsForAllStudents()
        columns = input.students
            .filter(\.isEnrolled)
            .map { student in
                let year = student.dateStarted.map {
                    CurriculumTimeline.enrollmentYear(anchor: $0, on: today, calendar: calendar)
                } ?? 1
                return ClassColumn(student: student, year: year)
            }
            .sorted(by: Self.cohortOrder)
        areas = Self.orderedAreas(input.lessons)
        let builder = RowBuilder(lessons: input.lessons, cells: all, students: columns.map(\.student))
        if let area, areas.contains(where: { Self.sameArea($0, area) }) {
            let areaLessons = input.lessons.filter { Self.sameArea($0.area, area) }
            sequences = Self.orderedSequences(in: area, lessons: areaLessons)
            let built = builder.sequenceRows(
                area: area, areaLessons: areaLessons, only: sequence, granularity: granularity
            )
            rows = Self.filter(built, by: stateFilter)
        } else {
            sequences = []
            rows = Self.filter(builder.greatLessonRows() + builder.areaRows(areas: areas), by: stateFilter)
        }
    }

    /// Children in the given state on a row, in column order.
    func students(in state: CurriculumCellState, on row: ClassRow) -> [CurriculumStudentRef] {
        columns.map(\.student).filter { row.state(for: $0.id) == state }
    }

    // MARK: - Ordering

    static func sameArea(_ lhs: String, _ rhs: String) -> Bool {
        CurriculumMapEngine.filingKey(lhs) == CurriculumMapEngine.filingKey(rhs)
    }

    /// Longest-enrolled first, then name — so the cohorts read as bands.
    static func cohortOrder(_ lhs: ClassColumn, _ rhs: ClassColumn) -> Bool {
        switch (lhs.student.dateStarted, rhs.student.dateStarted) {
        case let (l?, r?) where l != r: return l < r
        case (nil, .some): return false
        case (.some, nil): return true
        default:
            return lhs.student.fullName.localizedCaseInsensitiveCompare(rhs.student.fullName) == .orderedAscending
        }
    }

    private static func filter(_ rows: [ClassRow], by state: CurriculumCellState?) -> [ClassRow] {
        guard let state else { return rows }
        return rows.filter { row in
            if case .greatLessonsHeader = row.kind { return true }
            return (row.counts[state] ?? 0) > 0
        }
    }

    static func orderedAreas(_ lessons: [CurriculumLessonRef]) -> [String] {
        let unique = Set(lessons.map(\.area).filter { !$0.isEmpty })
        let existing = Array(unique).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return FilterOrderStore.loadAreaOrder(existing: existing)
    }

    static func orderedSequences(in area: String, lessons: [CurriculumLessonRef]) -> [String] {
        let unique = Set(lessons.map(\.sequence).filter { !$0.isEmpty })
        let existing = Array(unique).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        var ordered = FilterOrderStore.loadSequenceOrder(for: area, existing: existing)
        if lessons.contains(where: { $0.sequence.isEmpty }) { ordered.append("") }
        return ordered
    }
}

// MARK: - Row Builder

private struct RowBuilder {
    let lessons: [CurriculumLessonRef]
    let cells: [UUID: [UUID: CurriculumCell]]
    let students: [CurriculumStudentRef]

    func greatLessonRows() -> [ClassRow] {
        let byRaw = CurriculumMapEngine.greatLessonLessons(in: lessons)
        var rows: [ClassRow] = [
            ClassRow(
                kind: .greatLessonsHeader, title: "Great Lessons", subtitle: nil,
                tint: .accentColor, lessonIDs: [], cells: [:], counts: [:]
            )
        ]
        for great in GreatLesson.allCases {
            let stories = byRaw[great.rawValue] ?? []
            rows.append(row(
                kind: .greatLesson(great.rawValue), title: great.displayName,
                subtitle: stories.isEmpty ? "No lesson tagged" : stories.map(\.name).joined(separator: ", "),
                tint: great.color, lessonIDs: stories.map(\.id)
            ))
        }
        return rows
    }

    func areaRows(areas: [String]) -> [ClassRow] {
        areas.map { area in
            let ids = lessons
                .filter { CurriculumMapEngine.filingKey($0.area) == CurriculumMapEngine.filingKey(area) }
                .map(\.id)
            return row(
                kind: .area(area), title: area,
                subtitle: "\(ids.count) lessons — best state per child",
                tint: AppColors.color(forArea: area), lessonIDs: ids
            )
        }
    }

    func sequenceRows(
        area: String, areaLessons: [CurriculumLessonRef], only sequence: String?, granularity: CurriculumGranularity
    ) -> [ClassRow] {
        let tint = AppColors.color(forArea: area)
        let shownIDs = Set(CurriculumMapEngine.lessons(lessons, at: granularity).map(\.id))
        var rows: [ClassRow] = []
        for seq in ClassCurriculumMapModel.orderedSequences(in: area, lessons: areaLessons) {
            if let sequence, CurriculumMapEngine.filingKey(sequence) != CurriculumMapEngine.filingKey(seq) { continue }
            let inSequence = areaLessons
                .filter { CurriculumMapEngine.filingKey($0.sequence) == CurriculumMapEngine.filingKey(seq) }
                .sorted(by: CurriculumMapEngine.precedes)
            rows.append(row(
                kind: .sequence(area: area, sequence: seq), title: seq.isEmpty ? "Other" : seq,
                subtitle: "\(inSequence.count) lessons — best state per child",
                tint: tint, lessonIDs: inSequence.map(\.id)
            ))
            for lesson in inSequence where shownIDs.contains(lesson.id) {
                rows.append(row(
                    kind: .lesson(lesson.id), title: lesson.name,
                    subtitle: lesson.section.isEmpty ? nil : lesson.section, tint: tint,
                    lessonIDs: [lesson.id]
                ))
            }
        }
        return rows
    }

    private func row(
        kind: ClassRow.Kind, title: String, subtitle: String?, tint: Color, lessonIDs: [UUID]
    ) -> ClassRow {
        var glyphs: [UUID: CurriculumGlyphSpec] = [:]
        var counts: [CurriculumCellState: Int] = [:]
        for student in students {
            let studentCells = lessonIDs.compactMap { cells[student.id]?[$0] }
            let summary = CurriculumMapEngine.aggregate(studentCells, lessonCount: lessonIDs.count)
            counts[summary.state, default: 0] += 1
            if summary.state != .notPresented || summary.recall != nil {
                glyphs[student.id] = CurriculumGlyphSpec(state: summary.state, recall: summary.recall)
            }
        }
        return ClassRow(
            kind: kind, title: title, subtitle: subtitle, tint: tint,
            lessonIDs: lessonIDs, cells: glyphs, counts: counts
        )
    }
}
