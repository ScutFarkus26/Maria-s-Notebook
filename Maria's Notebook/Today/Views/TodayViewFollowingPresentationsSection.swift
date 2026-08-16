import SwiftUI

extension TodayView {
    var followingPresentationsListSection: some View {
        FollowingPresentationsView(
            style: .today,
            onOpen: { assignment in
                selectedLessonAssignment = assignment
            },
            onViewAll: {
                appRouter.navigateToLessonsAndWork(.needsAttention)
            }
        )
    }
}
