// ClassGridViewKind.swift
// The Class Grid's four views (Simplify the app, Decisions › Class Grid): the
// Checklist's grid and tools, Three Years (the old class Three-Year View),
// Children (the old Progress Dashboard) and Recall (the old Lesson Recall). One
// switch picks between them: a segmented control in the Mac toolbar, tabs
// under the title on iPad and iPhone.

import Foundation

/// What a search field looks through. A search typed for one kind means nothing
/// to another (a child's name is no lesson), so the grid empties it when the
/// field it shows looks through something else.
nonisolated enum ClassGridSearchTarget: Hashable, Sendable {
    case lessons
    case children
    case lessonsAndChildren
}

nonisolated enum ClassGridViewKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case checklist
    case threeYears
    case children
    case recall

    var id: String { rawValue }

    /// The switch's label: a noun, no icon (HIG, segmented controls).
    var title: String {
        switch self {
        case .checklist: "Checklist"
        case .threeYears: "Three Years"
        case .children: "Children"
        case .recall: "Recall"
        }
    }

    /// Whether the area menu offers "All areas". The Checklist always shows one
    /// area; the other three can show the whole curriculum.
    var allowsAllAreas: Bool { self != .checklist }

    /// What the view's search field looks through, or nil where it shows none:
    /// Three Years has no field, and neither does Recall on the iPhone.
    func searchTarget(isRegular: Bool) -> ClassGridSearchTarget? {
        switch self {
        case .checklist: .lessons
        case .threeYears: nil
        case .children: .children
        case .recall: isRegular ? .lessonsAndChildren : nil
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
    /// Checklist's destination; Three-Year View, Progress Dashboard and Lesson
    /// Recall are aliases of it (Phase 11), and each opens the Class Grid on
    /// its view through `NavigationItem.landing`.
    static func opening(_ item: RootView.NavigationItem) -> ClassGridViewKind? {
        switch item {
        case .planningChecklist: .checklist
        case .curriculumMap: .threeYears
        case .progressDashboard: .children
        case .lessonRecall: .recall
        default: nil
        }
    }
}
