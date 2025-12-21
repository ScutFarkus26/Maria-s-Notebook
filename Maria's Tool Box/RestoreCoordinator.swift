import Foundation
import Combine

final class RestoreCoordinator: ObservableObject {
    @Published var isRestoring: Bool = false
    private var cancellables: Set<AnyCancellable> = []

    init() {
        NotificationCenter.default.publisher(for: .AppDataWillBeReplaced)
            .sink { [weak self] _ in self?.isRestoring = true }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .AppDataDidRestore)
            .sink { [weak self] _ in self?.isRestoring = false }
            .store(in: &cancellables)
    }
}
