// ClassGridDestinations.swift
// The four screens the Class Grid replaced, kept as names that open the grid
// on their view. The sidebar routes the Checklist's destination straight to
// `ClassGridView`; Three-Year View, Progress Dashboard and Lesson Recall are
// aliases of it (Phase 11) and land on their view through `screenLanding`.

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
