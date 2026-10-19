// ClassGridYearsModel.swift
// The Class Grid's Three Years view (once the class Three-Year View): lessons
// (or areas) down the side, children across the top grouped by year in class,
// oldest first, so the cohorts read as bands, and each child's furthest mark on
// each row. This is the view for "who has not had the distributive law yet":
// the answer is a set of names.
//
// With "All areas" the rows are the Great Lessons, then one row per area; with
// an area picked, its sequences as bands and their key lessons (or all of them)
// as rows. The marks are the Checklist's (`ChecklistMark`), with the latest
// recall check drawn as a ring.

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
        case areasHeader
        case greatLesson(String)
        case area(String)
        case sequence(area: String, sequence: String)
        case lesson(UUID)

        var rowID: String {
            switch self {
            case .greatLessonsHeader: "great-lessons"
            case .areasHeader: "areas"
            case .greatLesson(let raw): "great-\(raw)"
            case .area(let area): "area-\(ClassGridEngine.filingKey(area))"
            case .sequence(let area, let sequence):
                "seq-\(ClassGridEngine.sequenceKey(area: area, sequence: sequence))"
            case .lesson(let id): "lesson-\(id.uuidString)"
            }
        }

        /// A band names what follows it and draws no marks.
        var isBand: Bool {
            switch self {
            case .greatLessonsHeader, .areasHeader, .sequence: true
            case .greatLesson, .area, .lesson: false
            }
        }
    }

    let kind: Kind
    let title: String
    let subtitle: String?
    let tint: Color
    let lessonIDs: [UUID]
    /// Child → mark. A missing child has nothing recorded: Not yet.
    let cells: [UUID: CurriculumGlyphSpec]
    let counts: [ChecklistDisplayStatus: Int]

    var id: String { kind.rowID }

    var lessonID: UUID? {
        if case .lesson(let id) = kind { return id }
        return nil
    }

    var isBand: Bool { kind.isBand }

    func state(for studentID: UUID) -> ChecklistDisplayStatus {
        cells[studentID]?.state ?? .notReady
    }

    /// The "Not yet" column: "Everyone", "3 not yet", over the children shown.
    func notYetText(over columns: [ClassColumn]) -> String {
        let count = columns.filter { state(for: $0.id) == .notReady }.count
        return count == 0 ? "Everyone" : "\(count) not yet"
    }
}

/// A run of columns in the same year in class: "YEAR 3 · 5".
struct ClassYearBlock: Identifiable, Hashable {
    let year: Int
    let count: Int
    var id: Int { year }
    var title: String { "\(CurriculumTimeline.yearBadge(year).uppercased()) · \(count)" }
}

@Observable
final class ClassGridYearsModel {
    private(set) var columns: [ClassColumn] = []
    private(set) var yearBlocks: [ClassYearBlock] = []
    /// The first child of every year block after the first, for the heavier rule.
    private(set) var blockStartIDs: Set<UUID> = []
    private(set) var rows: [ClassRow] = []
    private(set) var areas: [String] = []
    private(set) var sequences: [String] = []
    /// Lessons and sequences behind the rows, for the corner's counts.
    private(set) var lessonCount = 0

    // MARK: - Build

    /// `startMonth` and `startDay` are the school-year start (`SchoolYearStore`'s),
    /// passed in so the view rebuilds when the setting changes. `childIDs` empty
    /// shows every enrolled child; `query` keeps the rows whose name matches.
    func rebuild( // swiftlint:disable:this function_parameter_count
        store: CurriculumMapStore,
        area: String?,
        sequence: String?,
        granularity: CurriculumGranularity,
        stateFilter: ChecklistDisplayStatus?,
        startMonth: Int,
        startDay: Int,
        childIDs: Set<UUID> = [],
        query: String = "",
        today: Date = Date(),
        calendar: Calendar = AppCalendar.shared
    ) {
        guard let input = store.input else {
            columns = []
            yearBlocks = []
            blockStartIDs = []
            rows = []
            return
        }
        let all = store.cellsForAllStudents()
        columns = input.students
            .filter { $0.isEnrolled && (childIDs.isEmpty || childIDs.contains($0.id)) }
            .map { student in
                let year = student.dateStarted.map {
                    CurriculumTimeline.enrollmentYear(
                        anchor: $0, on: today, startMonth: startMonth, startDay: startDay, calendar: calendar
                    )
                } ?? 1
                return ClassColumn(student: student, year: year)
            }
            .sorted(by: Self.cohortOrder)
        (yearBlocks, blockStartIDs) = Self.blocks(for: columns)
        areas = Self.orderedAreas(input.lessons)
        let builder = RowBuilder(lessons: input.lessons, cells: all, students: columns.map(\.student))
        var built: [ClassRow]
        if let area, areas.contains(where: { Self.sameArea($0, area) }) {
            let areaLessons = input.lessons.filter { Self.sameArea($0.area, area) }
            sequences = Self.orderedSequences(in: area, lessons: areaLessons)
            built = builder.sequenceRows(
                area: area, areaLessons: areaLessons, only: sequence, granularity: granularity
            )
            lessonCount = built.filter { $0.lessonID != nil }.count
        } else {
            sequences = []
            built = builder.greatLessonRows() + builder.areaRows(areas: areas)
            lessonCount = input.lessons.count
        }
        built = Self.filter(built, by: stateFilter)
        rows = Self.filter(built, matching: query)
    }

    /// Children in the given state on a row, in column order.
    func students(in state: ChecklistDisplayStatus, on row: ClassRow) -> [CurriculumStudentRef] {
        columns.map(\.student).filter { row.state(for: $0.id) == state }
    }

    // MARK: - Ordering

    static func sameArea(_ lhs: String, _ rhs: String) -> Bool {
        ClassGridEngine.filingKey(lhs) == ClassGridEngine.filingKey(rhs)
    }

    /// Longest-enrolled first, then name — so the cohorts read as bands.
    static func cohortOrder(_ lhs: ClassColumn, _ rhs: ClassColumn) -> Bool {
        if lhs.year != rhs.year { return lhs.year > rhs.year }
        switch (lhs.student.dateStarted, rhs.student.dateStarted) {
        case let (l?, r?) where l != r: return l < r
        case (nil, .some): return false
        case (.some, nil): return true
        default:
            return lhs.student.fullName.localizedCaseInsensitiveCompare(rhs.student.fullName) == .orderedAscending
        }
    }

    /// The year blocks over `columns` (already in cohort order), and the first
    /// child of each block after the first.
    static func blocks(for columns: [ClassColumn]) -> ([ClassYearBlock], Set<UUID>) {
        var blocks: [ClassYearBlock] = []
        var starts = Set<UUID>()
        for column in columns {
            if let last = blocks.last, last.year == column.year {
                blocks[blocks.count - 1] = ClassYearBlock(year: last.year, count: last.count + 1)
            } else {
                if !blocks.isEmpty { starts.insert(column.id) }
                blocks.append(ClassYearBlock(year: column.year, count: 1))
            }
        }
        return (blocks, starts)
    }

    /// Rows with a child in `state`; the bands stay when a row under them does.
    private static func filter(_ rows: [ClassRow], by state: ChecklistDisplayStatus?) -> [ClassRow] {
        guard let state else { return rows }
        return keepingBands(rows) { ($0.counts[state] ?? 0) > 0 }
    }

    /// Rows whose name (or band) matches every word of `query`.
    private static func filter(_ rows: [ClassRow], matching query: String) -> [ClassRow] {
        let tokens = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return rows }
        return keepingBands(rows) { row in
            let text = (row.title + " " + (row.subtitle ?? "")).lowercased()
            return tokens.allSatisfy(text.contains)
        }
    }

    /// The rows that pass, each under the band it sat under; a band with no row
    /// left under it goes.
    private static func keepingBands(_ rows: [ClassRow], where passes: (ClassRow) -> Bool) -> [ClassRow] {
        var result: [ClassRow] = []
        var pendingBand: ClassRow?
        for row in rows {
            if row.isBand {
                pendingBand = row
            } else if passes(row) {
                if let band = pendingBand {
                    result.append(band)
                    pendingBand = nil
                }
                result.append(row)
            }
        }
        return result
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
        let byRaw = ClassGridEngine.greatLessonLessons(in: lessons)
        var rows: [ClassRow] = [
            band(.greatLessonsHeader, title: "Great Lessons", subtitle: "stories told to the whole class")
        ]
        for great in GreatLesson.allCases {
            let stories = byRaw[great.rawValue] ?? []
            rows.append(row(
                kind: .greatLesson(great.rawValue), title: great.displayName,
                subtitle: Self.storySubtitle(stories, title: great.displayName),
                tint: great.color, lessonIDs: stories.map(\.id)
            ))
        }
        return rows
    }

    /// The stories standing for a Great Lesson, unless the one story is named
    /// after it; "No lesson tagged" when none is.
    static func storySubtitle(_ stories: [CurriculumLessonRef], title: String) -> String? {
        guard !stories.isEmpty else { return "No lesson tagged" }
        let names = stories.map(\.name)
        if names.count == 1, ClassGridEngine.filingKey(names[0]) == ClassGridEngine.filingKey(title) { return nil }
        return names.joined(separator: ", ")
    }

    func areaRows(areas: [String]) -> [ClassRow] {
        var rows = [band(.areasHeader, title: "Areas", subtitle: "furthest mark per child")]
        rows += areas.map { area in
            let ids = lessons
                .filter { ClassGridEngine.filingKey($0.area) == ClassGridEngine.filingKey(area) }
                .map(\.id)
            return row(
                kind: .area(area), title: area,
                subtitle: "\(ids.count) lesson\(ids.count == 1 ? "" : "s")",
                tint: AppColors.color(forArea: area), lessonIDs: ids
            )
        }
        return rows
    }

    func sequenceRows(
        area: String, areaLessons: [CurriculumLessonRef], only sequence: String?, granularity: CurriculumGranularity
    ) -> [ClassRow] {
        let tint = AppColors.color(forArea: area)
        let shownIDs = Set(ClassGridEngine.lessons(lessons, at: granularity).map(\.id))
        var rows: [ClassRow] = []
        for seq in ClassGridYearsModel.orderedSequences(in: area, lessons: areaLessons) {
            if let sequence, ClassGridEngine.filingKey(sequence) != ClassGridEngine.filingKey(seq) { continue }
            let inSequence = areaLessons
                .filter { ClassGridEngine.filingKey($0.sequence) == ClassGridEngine.filingKey(seq) }
                .sorted(by: ClassGridEngine.precedes)
            let shown = inSequence.filter { shownIDs.contains($0.id) }
            guard !shown.isEmpty else { continue }
            rows.append(band(
                .sequence(area: area, sequence: seq), title: seq.isEmpty ? "Other" : seq,
                subtitle: "\(inSequence.count) lesson\(inSequence.count == 1 ? "" : "s")"
            ))
            for lesson in shown {
                rows.append(row(
                    kind: .lesson(lesson.id), title: lesson.name,
                    subtitle: lesson.section.isEmpty ? nil : lesson.section, tint: tint,
                    lessonIDs: [lesson.id]
                ))
            }
        }
        return rows
    }

    private func band(_ kind: ClassRow.Kind, title: String, subtitle: String) -> ClassRow {
        ClassRow(kind: kind, title: title, subtitle: subtitle, tint: .secondary, lessonIDs: [], cells: [:], counts: [:])
    }

    /// A row's furthest mark per child over its lessons, with the latest recall.
    private func row(
        kind: ClassRow.Kind, title: String, subtitle: String?, tint: Color, lessonIDs: [UUID]
    ) -> ClassRow {
        var glyphs: [UUID: CurriculumGlyphSpec] = [:]
        var counts: [ChecklistDisplayStatus: Int] = [:]
        for student in students {
            let studentCells = lessonIDs.compactMap { cells[student.id]?[$0] }
            let summary = ClassGridEngine.aggregate(studentCells, lessonCount: lessonIDs.count)
            counts[summary.state, default: 0] += 1
            if summary.state != .notReady || summary.recall != nil {
                glyphs[student.id] = CurriculumGlyphSpec(state: summary.state, recall: summary.recall)
            }
        }
        return ClassRow(
            kind: kind, title: title, subtitle: subtitle, tint: tint,
            lessonIDs: lessonIDs, cells: glyphs, counts: counts
        )
    }
}
