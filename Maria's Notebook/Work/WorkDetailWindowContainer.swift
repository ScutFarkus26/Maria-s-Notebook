import SwiftUI
import SwiftData

struct WorkDetailWindowContainer: View {
    let workID: UUID
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        WorkModelDetailSheet(workID: workID)
            #if os(macOS)
            .frame(minWidth: 500, minHeight: 400)
            #endif
    }
}
