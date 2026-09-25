// StudentCurriculumMapModel.swift
// Turns one child's cells into the rows the Three-Year View draws: the Great
// Lessons first, then every area, each expandable to its sequences and the key
// lessons inside them. Row aggregates and per-column glyphs are computed once
// per load and cached, so scrolling the grid costs nothing.

import Foundation
import SwiftUI

/// One row of the per-child grid.
struct CurriculumRow: Identifiable, Hashable {
    enum Kind: Hashable {
        case greatLessonsHeader
        case greatLesson(String)
        case area(String)
        case sequence(area: String, sequence: String)
        case lesson(UUID)
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String?
    let depth: Int
    let tint: Color
    let lessonIDs: [UUID]
    let summary: CurriculumAggregate
    var isExpanded = false
    var untouched: UntouchedFlag?
    /// Glyph per timeline column, nil where nothing happened.
    let glyphs: [CurriculumGlyphSpec?]

    var isExpandable: Bool {
        if case .area = kind { return true }
        return false
    }
}

struct CurriculumGlyphSpec: Hashable {
    let state: CurriculumCellState
    let recall: RecallOutcome?
}

struct UntouchedFlag: Hashable {
    let days: Int
    let lastPresented: Date?
    let lastActivity: Date?

    var text: String {
        guard let lastPresented else { return "Never presented" }
        return "No presentation since \(DateFormatters.mediumDate.string(from: lastPresented))"
    }
}

@Observable
final class StudentCurriculumMapModel {
    private(set) var rows: [CurriculumRow] = []
    private(set) var timeline: CurriculumTimeline?
    private(set) var student: CurriculumStudentRef?
    private(set) var untouchedAreaCount = 0
    var expandedAreas: Set<String> = []

    private var allRows: [CurriculumRow] = []

    // MARK: - Build

    func rebuild(
        studentID: UUID,
        store: CurriculumMapStore,
        settings: CurriculumMapSettings,
        zoom: CurriculumZoom,
        granularity: CurriculumGranularity,
        today: Date = Date(),
        calendar: Calendar = AppCalendar.shared
    ) {
        guard let input = store.input, let student = store.student(studentID) else {
            rows = []
            return
        }
        self.student = student
        let cells = store.cells(for: studentID)
        let earliest = cells.values.compactMap { $0.events.first?.date }.min()
        let timeline = CurriculumTimeline.make(
            dateStarted: student.dateStarted, fallbackAnchor: earliest, today: today, zoom: zoom, calendar: calendar
        )
        self.timeline = timeline

        let builder = RowBuilder(
            lessons: input.lessons, cells: cells, timeline: timeline, settings: settings,
            granularity: granularity, today: today, calendar: calendar
        )
        allRows = builder.greatLessonRows() + builder.areaRows()
        untouchedAreaCount = allRows.filter { $0.untouched != nil }.count
        applyExpansion()
    }

    func toggle(area: String) {
        let key = CurriculumMapEngine.filingKey(area)
        if expandedAreas.contains(key) { expandedAreas.remove(key) } else { expandedAreas.insert(key) }
        applyExpansion()
    }

    func expandAll() {
        expandedAreas = Set(allRows.compactMap { row in
            if case .area(let area) = row.kind { return CurriculumMapEngine.filingKey(area) }
            return nil
        })
        applyExpansion()
    }

    func collapseAll() {
        expandedAreas = []
        applyExpansion()
    }

    private func applyExpansion() {
        var visible: [CurriculumRow] = []
        var currentAreaExpanded = false
        for var row in allRows {
            switch row.kind {
            case .greatLessonsHeader, .greatLesson:
                visible.append(row)
            case .area(let area):
                currentAreaExpanded = expandedAreas.contains(CurriculumMapEngine.filingKey(area))
                row.isExpanded = currentAreaExpanded
                visible.append(row)
            case .sequence, .lesson:
                if currentAreaExpanded { visible.append(row) }
            }
        }
        rows = visible
    }
}

// MARK: - Row Builder

private struct RowBuilder {
    let lessons: [CurriculumLessonRef]
    let cells: [UUID: CurriculumCell]
    let timeline: CurriculumTimeline
    let settings: CurriculumMapSettings
    let granularity: CurriculumGranularity
    let today: Date
    let calendar: Calendar

    private var firstLessonIDs: Set<UUID> { CurriculumMapEngine.firstLessonIDs(in: lessons) }

    func greatLessonRows() -> [CurriculumRow] {
        let byRaw = CurriculumMapEngine.greatLessonLessons(in: lessons)
        var rows: [CurriculumRow] = [
            CurriculumRow(
                id: "great-lessons", kind: .greatLessonsHeader, title: "Great Lessons",
                subtitle: "The spine of the plane, given to everyone each year", depth: 0,
                tint: .accentColor, lessonIDs: [], summary: .empty, glyphs: emptyGlyphs()
            )
        ]
        for great in GreatLesson.allCases {
            let storyLessons = byRaw[great.rawValue] ?? []
            let ids = storyLessons.map(\.id)
            let summary = aggregate(for: ids)
            rows.append(CurriculumRow(
                id: "great-\(great.rawValue)",
                kind: .greatLesson(great.rawValue),
                title: great.displayName,
                subtitle: storyLessons.isEmpty
                    ? "No lesson tagged — tag the story in its lesson editor"
                    : storyLessons.map(\.name).joined(separator: ", "),
                depth: 1,
                tint: great.color,
                lessonIDs: ids,
                summary: summary,
                glyphs: glyphs(for: summary.events)
            ))
        }
        return rows
    }

    func areaRows() -> [CurriculumRow] {
        let shownLessons = CurriculumMapEngine.lessons(lessons, at: granularity)
        let areas = orderedAreas()
        var rows: [CurriculumRow] = []
        for area in areas {
            let areaKey = CurriculumMapEngine.filingKey(area)
            let areaLessons = lessons.filter { CurriculumMapEngine.filingKey($0.area) == areaKey }
            let ids = areaLessons.map(\.id)
            let summary = aggregate(for: ids)
            let days = settings.untouchedDays(for: area)
            let untouched = CurriculumMapEngine.isUntouched(
                lastPresented: summary.lastPresented, days: days, today: today, calendar: calendar
            )
            rows.append(CurriculumRow(
                id: "area-\(CurriculumMapEngine.filingKey(area))",
                kind: .area(area),
                title: area,
                subtitle: "\(summary.presentedCount) of \(areaLessons.count) presented",
                depth: 0,
                tint: AppColors.color(forArea: area),
                lessonIDs: ids,
                summary: summary,
                untouched: untouched ? UntouchedFlag(
                    days: days, lastPresented: summary.lastPresented, lastActivity: summary.lastActivity
                ) : nil,
                glyphs: glyphs(for: summary.events)
            ))
            rows.append(contentsOf: sequenceRows(area: area, areaLessons: areaLessons, shown: shownLessons))
        }
        return rows
    }

    private func sequenceRows(
        area: String, areaLessons: [CurriculumLessonRef], shown: [CurriculumLessonRef]
    ) -> [CurriculumRow] {
        let tint = AppColors.color(forArea: area)
        let shownIDs = Set(shown.map(\.id))
        var rows: [CurriculumRow] = []
        for sequence in orderedSequences(in: area, lessons: areaLessons) {
            let inSequence = areaLessons
                .filter { CurriculumMapEngine.filingKey($0.sequence) == CurriculumMapEngine.filingKey(sequence) }
                .sorted(by: CurriculumMapEngine.precedes)
            let summary = aggregate(for: inSequence.map(\.id))
            rows.append(CurriculumRow(
                id: "seq-\(CurriculumMapEngine.sequenceKey(area: area, sequence: sequence))",
                kind: .sequence(area: area, sequence: sequence),
                title: sequence.isEmpty ? "Other" : sequence,
                subtitle: "\(summary.presentedCount) of \(inSequence.count)",
                depth: 1,
                tint: tint,
                lessonIDs: inSequence.map(\.id),
                summary: summary,
                glyphs: glyphs(for: summary.events)
            ))
            for lesson in inSequence where shownIDs.contains(lesson.id) {
                let cell = cells[lesson.id] ?? CurriculumCell(studentID: UUID(), lessonID: lesson.id)
                var summary = CurriculumAggregate()
                summary.state = cell.state
                summary.recall = cell.recall
                summary.firstPresented = cell.firstPresented
                summary.lastPresented = cell.lastPresented
                summary.lastActivity = cell.lastActivity
                summary.lessonCount = 1
                summary.presentedCount = cell.state >= .presented ? 1 : 0
                summary.events = cell.events
                rows.append(CurriculumRow(
                    id: "lesson-\(lesson.id.uuidString)",
                    kind: .lesson(lesson.id),
                    title: lesson.name,
                    subtitle: lessonSubtitle(lesson, cell: cell),
                    depth: 2,
                    tint: tint,
                    lessonIDs: [lesson.id],
                    summary: summary,
                    glyphs: glyphs(for: cell.events)
                ))
            }
        }
        return rows
    }

    private func lessonSubtitle(_ lesson: CurriculumLessonRef, cell: CurriculumCell) -> String? {
        var parts: [String] = []
        if CurriculumMapEngine.isKeyLesson(lesson, firstLessonIDs: firstLessonIDs) { parts.append("Key lesson") }
        if let first = cell.firstPresented {
            parts.append("presented \(DateFormatters.mediumDate.string(from: first))")
        }
        if cell.practiceCount > 0 { parts.append("\(cell.practiceCount) practice") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Helpers

    private func aggregate(for lessonIDs: [UUID]) -> CurriculumAggregate {
        CurriculumMapEngine.aggregate(lessonIDs.compactMap { cells[$0] }, lessonCount: lessonIDs.count)
    }

    /// The best thing that happened in each column, with the latest recall in it.
    private func glyphs(for events: [CurriculumEvent]) -> [CurriculumGlyphSpec?] {
        var best: [CurriculumCellState?] = Array(repeating: nil, count: timeline.columns.count)
        var recall: [(Date, RecallOutcome)?] = Array(repeating: nil, count: timeline.columns.count)
        for event in events {
            guard let index = timeline.columnIndex(for: event.date) else { continue }
            if let state = event.state {
                best[index] = max(best[index] ?? .notPresented, state)
            }
            if let outcome = event.recall, recall[index] == nil || event.date > recall[index]!.0 {
                recall[index] = (event.date, outcome)
            }
        }
        return (0..<timeline.columns.count).map { index in
            guard best[index] != nil || recall[index] != nil else { return nil }
            return CurriculumGlyphSpec(state: best[index] ?? .notPresented, recall: recall[index]?.1)
        }
    }

    private func emptyGlyphs() -> [CurriculumGlyphSpec?] {
        Array(repeating: nil, count: timeline.columns.count)
    }

    /// Areas in the scope map's saved order, so the grid reads like the Lessons screen.
    private func orderedAreas() -> [String] {
        let unique = Set(lessons.map(\.area).filter { !$0.isEmpty })
        let existing = Array(unique).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return FilterOrderStore.loadAreaOrder(existing: existing)
    }

    private func orderedSequences(in area: String, lessons: [CurriculumLessonRef]) -> [String] {
        let unique = Set(lessons.map(\.sequence).filter { !$0.isEmpty })
        let existing = Array(unique).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        var ordered = FilterOrderStore.loadSequenceOrder(for: area, existing: existing)
        if lessons.contains(where: { $0.sequence.isEmpty }) { ordered.append("") }
        return ordered
    }
}
