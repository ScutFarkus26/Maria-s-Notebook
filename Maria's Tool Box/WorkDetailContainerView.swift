import SwiftUI
import SwiftData

struct WorkDetailContainerView: View {
    let workID: UUID
    var onDone: (() -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        WorkDetailWindowContainer(workID: workID)
            #if os(macOS)
            .frame(minWidth: 720, minHeight: 640)
            .presentationSizing(.fitted)
            #else
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            #endif
    }
}

#if DEBUG
struct WorkDetailContainerView_Previews: PreviewProvider {
    static var previews: some View {
        WorkDetailContainerView(workID: UUID())
    }
}
#endif
