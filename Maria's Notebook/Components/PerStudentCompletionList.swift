import SwiftUI
import CoreData

struct StudentLite: Identifiable, Hashable {
    let id: UUID
    let name: String
}

struct PerStudentCompletionList: View {
    let workID: UUID
    let students: [StudentLite]

    var body: some View {
        Section(header: header) {
            ForEach(students) { student in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(student.name)
                            .font(.headline)
                        NavigationLink {
                            WorkCompletionHistoryView(workID: workID, studentID: student.id)
                        } label: {
                            Label("History", systemImage: "clock.arrow.circlepath")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    MarkCompletionButton(workID: workID, studentID: student.id, label: "Completed")
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Per-CDStudent Completion")
                .font(.subheadline).bold()
            Text("Mark completions for each student and view their history.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    struct PreviewHost: View {
        let workID = UUID()
        let students: [StudentLite] = [
            .init(id: UUID(), name: "Ava"),
            .init(id: UUID(), name: "Liam"),
            .init(id: UUID(), name: "Noah")
        ]
        var body: some View {
            NavigationStack {
                List {
                    PerStudentCompletionList(workID: workID, students: students)
                }
            }
        }
    }

    return PreviewHost()
        .previewEnvironment()
}
