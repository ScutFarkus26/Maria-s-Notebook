import SwiftUI

struct InboxViewContent: View {
    let lessonAssignments: [CDLessonAssignment]
    let orderedUnscheduledLessons: [CDLessonAssignment]
    @Binding var inboxOrderRaw: String
    let onOpenDetails: (UUID) -> Void
    let onQuickActions: (UUID) -> Void
    let onPlanNext: (CDLessonAssignment) -> Void
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
