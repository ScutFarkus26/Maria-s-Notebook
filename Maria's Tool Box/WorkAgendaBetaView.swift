import SwiftUI
import SwiftData

// WorkAgendaBetaView has been refactored to use the new WorksAgendaView layout.
// Legacy implementation removed to avoid duplication. If you need the old UI for reference,
// check version control history. This wrapper keeps the navigation entry point stable.
struct WorkAgendaBetaView: View {
    var body: some View {
        WorksAgendaView()
    }
}

#Preview {
    let schema = AppSchema.schema
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: configuration)
    let ctx = container.mainContext
    // Seed minimal data
    let s = Student(firstName: "Ada", lastName: "Lovelace", birthday: Date(), level: .upper)
    let l = Lesson(name: "Long Division", subject: "Math", group: "Ops", subheading: "", writeUp: "")
    ctx.insert(s); ctx.insert(l)
    let c = WorkContract(studentID: s.id.uuidString, lessonID: l.id.uuidString, presentationID: nil, status: .active)
    ctx.insert(c)

    return WorkAgendaBetaView()
        .previewEnvironment(using: container)
        .environmentObject(SaveCoordinator.preview)
}

