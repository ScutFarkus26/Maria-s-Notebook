import Foundation
import Combine

final class RestoreCoordinator: ObservableObject {
    @Published var isRestoring: Bool = false
    private var cancellables: Set<AnyCancellable> = []
    private let appRouter = AppRouter.shared

    init() {
        appRouter.$appDataWillBeReplaced
            .sink { [weak self] willBeReplaced in
                if willBeReplaced {
                    self?.isRestoring = true
                }
            }
            .store(in: &cancellables)
        appRouter.$appDataDidRestore
            .sink { [weak self] didRestore in
                if didRestore {
                    self?.isRestoring = false
                }
            }
            .store(in: &cancellables)
    }
}
