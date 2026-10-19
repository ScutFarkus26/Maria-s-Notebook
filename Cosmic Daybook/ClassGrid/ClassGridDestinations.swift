// ClassGridDestinations.swift
// The four sidebar destinations the Class Grid replaces, kept as the names
// `RootDetailContent` routes to until Phase 11 aliases the old three to the
// Checklist's destination. Each opens the Class Grid on its view; the screens
// they used to be are gone.

import SwiftUI

/// The Checklist's destination (`.planningChecklist`): the Class Grid itself.
struct ClassAreaChecklistView: View {
    let initialView = ClassGridViewKind.checklist

    var body: some View {
        ClassGridView(initialView: initialView)
    }
}

/// The Three-Year View's destination (`.curriculumMap`): the Class Grid on Three Years.
/// The child's own Three-Year View on her page is `StudentCurriculumMapView`.
struct ClassCurriculumMapView: View {
    let initialView = ClassGridViewKind.threeYears

    var body: some View {
        ClassGridView(initialView: initialView)
    }
}

/// The Progress Dashboard's destination (`.progressDashboard`): the Class Grid on Children.
struct ProgressDashboardView: View {
    let initialView = ClassGridViewKind.children

    /// What the Children view reloads on; kept here under the old name for the
    /// screen it replaced.
    static let reloadEntityNames = ClassGridChildrenView.reloadEntityNames

    var body: some View {
        ClassGridView(initialView: initialView)
    }
}

/// Lesson Recall's destination (`.lessonRecall`): the Class Grid on Recall.
struct RecallQueueView: View {
    let initialView = ClassGridViewKind.recall

    var body: some View {
        ClassGridView(initialView: initialView)
    }
}
