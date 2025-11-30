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
            VStack(spacing: 12) {
                Text("Work not found")
                    .font(.headline)
                Button("Close") { dismiss() }
            }
            .frame(minWidth: 400, minHeight: 300)
        }
    }
}
