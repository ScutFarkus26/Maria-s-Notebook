import SwiftUI
import CoreData

/// Traffic Director: Routes to platform-specific implementations.
/// - macOS: Uses @Query for automatic, real-time updates (the "Magic")
/// - iOS: Uses manual NSFetchRequest for battery optimization
@MainActor
struct PlanningWeekView: View {
    var body: some View {
        #if os(macOS)
        PlanningWeekViewMac()
        #else
        PlanningWeekViewiOS()
        #endif
    }
}

#Preview {
    PlanningWeekView()
        .frame(minWidth: 1000, minHeight: 600)
}
