import SwiftUI

struct InboxViewContent: View {
    let lessonAssignments: [LessonAssignment]
    let orderedUnscheduledLessons: [LessonAssignment]
    @Binding var inboxOrderRaw: String
    let onOpenDetails: (UUID) -> Void
    let onQuickActions: (UUID) -> Void
    let onPlanNext: (LessonAssignment) -> Void
    let onUpdateOrder: (String) -> Void

    var body: some View {
        InboxSheetView(
            lessonAssignments: lessonAssignments,
            orderedUnscheduledLessons: orderedUnscheduledLessons,
            inboxOrderRaw: $inboxOrderRaw,
            onOpenDetails: onOpenDetails,
            onQuickActions: onQuickActions,
            onPlanNext: onPlanNext,
            onUpdateOrder: onUpdateOrder
        )
    }
}
