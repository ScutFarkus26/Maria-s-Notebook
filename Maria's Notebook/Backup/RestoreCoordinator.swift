import Foundation
import Observation

@Observable
@MainActor
final class RestoreCoordinator {
    var isRestoring: Bool = false
    private let appRouter: AppRouter

    init(appRouter: AppRouter = AppRouter.shared) {
        self.appRouter = appRouter
        // Use withObservationTracking to observe @Observable AppRouter
        observeAppRouter()
    }
    
    private func observeAppRouter() {
        Task { @MainActor in
            withObservationTracking {
                // Track changes to appRouter properties
                _ = appRouter.appDataWillBeReplaced
                _ = appRouter.appDataDidRestore
            } onChange: {
                // When changes occur, update our state and re-observe
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if self.appRouter.appDataWillBeReplaced {
                        self.isRestoring = true
                    }
                    if self.appRouter.appDataDidRestore {
                        self.isRestoring = false
                    }
                    // Re-establish observation
                    self.observeAppRouter()
                }
            }
        }
    }
}
