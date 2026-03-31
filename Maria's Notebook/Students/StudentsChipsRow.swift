import SwiftUI
import CoreData

struct StudentsChipsRow: View {
    let students: [CDStudent]
    @Binding var selectedIDs: Set<UUID>
    let subjectColor: Color
    let onManage: () -> Void

    private func displayName(for student: CDStudent) -> String {
        let nameParts = student.fullName.split(separator: " ")
        guard let firstName = nameParts.first else {
            return student.fullName
        }
        let lastInitial = nameParts.dropFirst().first?.prefix(1) ?? ""
        return "\(firstName) \(lastInitial)."
    }

    var body: some View {
        HStack {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(
                        students.filter { $0.id.map { selectedIDs.contains($0) } ?? false }
                            .sorted(by: StudentSortComparator.byFirstName),
                        id: \.objectID
                    ) { student in
                        HStack(spacing: 4) {
                            Text(displayName(for: student))
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Button {
                                if let id = student.id { selectedIDs.remove(id) }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(displayName(for: student))")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(subjectColor.opacity(UIConstants.OpacityConstants.accent))
                        .clipShape(Capsule())
                    }
                }
                .padding(.vertical, 4)
            }

            Button {
                onManage()
            } label: {
                Label("Manage Students", systemImage: "person.2.badge.plus")
            }
        }
    }
}
