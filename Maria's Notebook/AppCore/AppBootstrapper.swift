import Foundation
import SwiftData
import SwiftUI
import Combine

/// Handles the initial setup and database migrations for the app.
/// Moves heavy synchronous work off the main UI rendering flow of the App struct.
@MainActor
final class AppBootstrapper: ObservableObject {
    enum State {
        case idle
        case migrating
        case ready
    }
    
    @Published private(set) var state: State = .idle
    
    static let shared = AppBootstrapper()
    private init() {}
    
    func bootstrap(modelContainer: ModelContainer) async {
        guard state == .idle else { return }
        state = .migrating
        
        let context = modelContainer.mainContext
        
        print("AppBootstrapper: Starting startup checks...")
        
        // 1. Calendar Setup
        AppCalendar.adopt(timeZoneFrom: Calendar.current)
        
        // 2. Critical Data Repairs
        // (Completed and removed)
        
        // 3. Schema & Data Normalization (WorkModel logic disabled)
        DataMigrations.normalizeGivenAtToDateOnlyIfNeeded(using: context)
        
        // 3.5. Fix CommunityTopic tags type mismatch
        DataMigrations.fixCommunityTopicTagsIfNeeded(using: context)
        
        // 4. Legacy Data (Run asynchronously without awaiting if it's safe, or await if dependent)
        LegacyNotesMigration.runIfNeeded(modelContext: context)
        
        // 5. Signal UI
        AppRouter.shared.refreshPlanningInbox()
        
        print("AppBootstrapper: Startup checks complete.")
        state = .ready
    }
}
