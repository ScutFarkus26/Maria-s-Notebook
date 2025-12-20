import SwiftUI
import SwiftData

// DEPRECATED WRAPPER: WorkAgendaBetaView is now the permanent Work Agenda.
// This type remains temporarily to avoid widespread renames. It simply hosts the canonical WorksAgendaView.
// You can safely delete this file after renaming references to WorksAgendaView.
struct WorkAgendaBetaView: View {
    var body: some View {
        WorksAgendaView()
    }
}

#Preview {
    let schema = AppSchema.schema
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: configuration)
    return WorkAgendaBetaView()
        .previewEnvironment(using: container)
        .environmentObject(SaveCoordinator.preview)
}

