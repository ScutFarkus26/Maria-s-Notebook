//
//  ChecklistGridMetrics.swift
//  Cosmic Daybook
//
//  The checklist grid's sizes. The Mac and a regular-width iPad get the dense layout
//  (38-pt columns under angled names grouped by level, a one-line lesson column, a
//  Class column, 30-pt rows); an iPhone keeps its 120-pt columns, two-line lesson
//  names and the name-and-age header.
//

import SwiftUI

struct ChecklistGridMetrics: Equatable {
    let isRegular: Bool
    let studentColumnWidth: CGFloat
    let lessonColumnWidth: CGFloat
    let rowHeight: CGFloat
    /// 0 when the layout has no Class column.
    let classColumnWidth: CGFloat
    let headerHeight: CGFloat
    let sequenceBandHeight: CGFloat
    let sectionCaptionHeight: CGFloat

    static let regular = ChecklistGridMetrics(
        isRegular: true,
        studentColumnWidth: 38,
        lessonColumnWidth: 268,
        rowHeight: 30,
        classColumnWidth: 116,
        headerHeight: levelBandHeight + 90,
        sequenceBandHeight: 30,
        sectionCaptionHeight: 24
    )

    static let compact = ChecklistGridMetrics(
        isRegular: false,
        studentColumnWidth: 120,
        lessonColumnWidth: 200,
        rowHeight: 44,
        classColumnWidth: 0,
        headerHeight: 44,
        sequenceBandHeight: 34,
        sectionCaptionHeight: 26
    )

    /// The strip above the angled names that labels each level block.
    static let levelBandHeight: CGFloat = 22

    /// Full width of one row: lesson column, student columns, Class column.
    func rowWidth(studentCount: Int) -> CGFloat {
        lessonColumnWidth + CGFloat(studentCount) * studentColumnWidth + classColumnWidth
    }

    /// The narrowest the Mac and iPad lesson column goes to make room for the class.
    static let minimumLessonColumnWidth: CGFloat = 200

    /// These metrics with the lesson column narrowed, down to `minimumLessonColumnWidth`,
    /// so that `studentCount` columns and the Class column fit in `width`: a full class
    /// of 22 fits an 1180-pt iPad window. Never wider than its natural width; unchanged
    /// on the iPhone and before the grid has been measured (`width` 0).
    func fitted(toWidth width: CGFloat, studentCount: Int) -> ChecklistGridMetrics {
        guard isRegular, width > 0 else { return self }
        let room = width - CGFloat(studentCount) * studentColumnWidth - classColumnWidth
        let fitted = min(lessonColumnWidth, max(Self.minimumLessonColumnWidth, room.rounded(.down)))
        guard fitted != lessonColumnWidth else { return self }
        return ChecklistGridMetrics(
            isRegular: isRegular,
            studentColumnWidth: studentColumnWidth,
            lessonColumnWidth: fitted,
            rowHeight: rowHeight,
            classColumnWidth: classColumnWidth,
            headerHeight: headerHeight,
            sequenceBandHeight: sequenceBandHeight,
            sectionCaptionHeight: sectionCaptionHeight
        )
    }

    // MARK: - Colors

    /// What the grid draws on: white in light mode on both platforms.
    static var surface: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }

    /// A row's bottom hairline.
    static let hairline = Color.primary.opacity(UIConstants.OpacityConstants.subtle)
    /// The heavier rule between level blocks and above a sequence band.
    static let blockRule = Color.primary.opacity(0.22)
    /// The faint fill of a sequence band and the level band.
    static let bandFill = Color.primary.opacity(UIConstants.OpacityConstants.whisper)
    /// The pointer's row and column: a faint wash of the accent (the canvas's hover blue).
    static let hoverFill = Color.accentColor.opacity(0.09)
    /// The Ready lens's tile behind a ready cell: a light blue wash in light mode, a deep
    /// one in dark mode, under the mark's blue ring.
    static let readyTile = Color.blue.opacity(0.15)
}
