// ClassGridViewKind.swift
// The Class Grid's three views (Simplify the app, Decisions › Class Grid): the
// Checklist's grid and tools, Three Years (the old class Three-Year View) and
// Children (the old Progress Dashboard). One switch picks between them: a
// segmented control in the Mac toolbar, tabs under the title on iPad and
// iPhone. Recall (the old Lesson Recall) was taken out on 2026-11-21; past
// checks still show in the rings and the Three-Year View.

import Foundation

/// What a search field looks through. A search typed for one kind means nothing
/// to another (a child's name is no lesson), so the grid empties it when the
/// field it shows looks through something else.
nonisolated enum ClassGridSearchTarget: Hashable, Sendable {
    case lessons
    case children
}

nonisolated enum ClassGridViewKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case checklist
    case threeYears
    case children

    var id: String { rawValue }

    /// The switch's label: a noun, no icon (HIG, segmented controls).
    var title: String {
        switch self {
        case .checklist: "Checklist"
        case .threeYears: "Three Years"
        case .children: "Children"
        }
    }

    /// Whether the area menu offers "All areas". The Checklist always shows one
    /// area; the other two can show the whole curriculum.
    var allowsAllAreas: Bool { self != .checklist }

    /// What the view's search field looks through, or nil where it shows none:
    /// Three Years has no field.
    func searchTarget(isRegular: Bool) -> ClassGridSearchTarget? {
        switch self {
        case .checklist: .lessons
        case .threeYears: nil
        case .children: .children
        }
    }

    /// "Click" with a pointer, "Tap" on a touch screen, for the grid's hint lines.
    static var pointVerb: String {
        #if os(macOS)
        "Click"
        #else
        "Tap"
        #endif
    }

    /// The view an old destination opens on. The Class Grid lives at the
    /// Checklist's destination; Three-Year View and Progress Dashboard are
    /// aliases of it (Phase 11), and each opens the Class Grid on its view
    /// through `NavigationItem.landing`. Lesson Recall, an alias too, opens it
    /// as it is (Recall was taken out on 2026-11-21).
    static func opening(_ item: RootView.NavigationItem) -> ClassGridViewKind? {
        switch item {
        case .planningChecklist: .checklist
        case .curriculumMap: .threeYears
        case .progressDashboard: .children
        default: nil
        }
    }
}
