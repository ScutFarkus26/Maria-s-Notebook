import SwiftUI

struct InboxViewContent: View {
    let studentLessons: [StudentLesson]
    let orderedUnscheduledLessons: [StudentLesson]
    @Binding var inboxOrderRaw: String
    let onOpenDetails: (UUID) -> Void
    let onQuickActions: (UUID) -> Void
    let onPlanNext: (StudentLesson) -> Void
    let onUpdateOrder: (String) -> Void

    var body: some View {
        InboxSheetView(
            studentLessons: studentLessons,
            orderedUnscheduledLessons: orderedUnscheduledLessons,
            inboxOrderRaw: $inboxOrderRaw,
            onOpenDetails: onOpenDetails,
            onQuickActions: onQuickActions,
            onPlanNext: onPlanNext,
            onUpdateOrder: onUpdateOrder
        )
    }
}
