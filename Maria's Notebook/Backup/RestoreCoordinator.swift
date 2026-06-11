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
        Task { @MainActor [weak self] in
            guard let self else { return }
            withObservationTracking {
                // CDTrackEntity changes to appRouter properties
                _ = self.appRouter.appDataWillBeReplaced
                _ = self.appRouter.appDataDidRestore
            } onChange: { [weak self] in
                // When changes occur, update our state and re-observe
                Task { @MainActor in
                    guard let self else { return }
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
