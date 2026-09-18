import SwiftUI

struct InboxViewContent: View {
    let lessonAssignments: [CDLessonAssignment]
    let orderedUnscheduledLessons: [CDLessonAssignment]
    /// The curriculum and the roster the inbox pills name, held by the parent
    /// so no pill fetches either table for itself.
    let lessons: [CDLesson]
    let students: [CDStudent]
    @Binding var inboxOrderRaw: String
    let onOpenDetails: (UUID) -> Void
    let onQuickActions: (UUID) -> Void
    let onPlanNext: (CDLessonAssignment) -> Void
    let onUpdateOrder: (String) -> Void

    var body: some View {
        InboxSheetView(
            lessonAssignments: lessonAssignments,
            orderedUnscheduledLessons: orderedUnscheduledLessons,
            lessons: lessons,
            students: students,
            inboxOrderRaw: $inboxOrderRaw,
            onOpenDetails: onOpenDetails,
            onQuickActions: onQuickActions,
            onPlanNext: onPlanNext,
            onUpdateOrder: onUpdateOrder
        )
    }
}
