// LessonAssignmentBridges.swift
// Bridge views that pass LessonAssignment directly to detail and quick-action views.

import SwiftUI

// MARK: - Detail Bridge

struct LessonAssignmentDetailBridge: View {
    let lessonAssignment: LessonAssignment
    let onDone: () -> Void

    var body: some View {
        StudentLessonDetailView(lessonAssignment: lessonAssignment, onDone: onDone)
    }
}

// MARK: - Quick Actions Bridge

struct LessonAssignmentQuickActionsBridge: View {
    let lessonAssignment: LessonAssignment
    let onDone: () -> Void

    var body: some View {
        StudentLessonQuickActionsView(lessonAssignment: lessonAssignment, onDone: onDone)
    }
}
