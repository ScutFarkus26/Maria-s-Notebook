import SwiftUI
import Combine
import SwiftData

/// Compatibility shim for legacy references to `WorkDetailViewModel`.
/// The Work detail UI has migrated to `WorkContractDetailSheet` and related views.
/// This class exists to satisfy any remaining references during the transition.
@MainActor
@available(*, deprecated, message: "Use WorkContractDetailSheet / WorkContract instead of WorkModel + WorkDetailViewModel.")
final class WorkDetailViewModel: ObservableObject, Identifiable {
    let id = UUID()
    let workID: UUID

    // Legacy compatibility: some views bind to this list via `$vm.selectedStudentsList`
    @Published var selectedStudentsList: [Student] = []

    // Legacy compatibility: completion toggles per-student
    @Published var isStudentCompletedDraft: [UUID: Bool] = [:]

    // Legacy API used by some views
    func setStudentCompletedDraft(_ studentID: UUID, _ value: Bool) {
        isStudentCompletedDraft[studentID] = value
    }

    // Convenience binding for dictionary-backed toggle
    func bindingIsStudentCompleted(for studentID: UUID) -> Binding<Bool> {
        Binding(
            get: { self.isStudentCompletedDraft[studentID] ?? false },
            set: { self.isStudentCompletedDraft[studentID] = $0 }
        )
    }

    init(workID: UUID) {
        self.workID = workID
    }

    /// Convenience initializer for legacy call sites that passed a WorkModel.
    convenience init(work: WorkModel) {
        self.init(workID: work.id)
    }
}

