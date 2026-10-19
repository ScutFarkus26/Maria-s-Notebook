// ClassGridViewKind.swift
// The Class Grid's four views (Simplify the app, Decisions › Class Grid): the
// Checklist's grid and tools, Three Years (the old class Three-Year View),
// Children (the old Progress Dashboard) and Recall (the old Lesson Recall). One
// switch picks between them: a segmented control in the Mac toolbar, tabs
// under the title on iPad and iPhone.

import Foundation

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
