import SwiftUI
import SwiftData

struct WorkDetailWindowContainer: View {
    let workID: UUID

    @Environment(\.dismiss) private var dismiss
    @Query private var works: [WorkModel]

    init(workID: UUID) {
        self.workID = workID
        _works = Query(filter: #Predicate<WorkModel> { $0.id == workID })
    }

    var body: some View {
        if let work = works.first {
            WorkDetailView(work: work) {
                dismiss()
            }
            .frame(minWidth: 520, minHeight: 560)
        } else {
            // Auto-dismiss the window when the work is missing (e.g., deleted)
            Color.clear
                .frame(minWidth: 1, minHeight: 1)
                .onAppear { dismiss() }
        }
    }
}
