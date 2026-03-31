import SwiftUI
import CoreData

struct StudentFilterView: View {
    @Binding var selectedStudentIDs: Set<UUID>
    let students: [CDStudent]
    let displayName: (CDStudent) -> String
    var onDismiss: () -> Void
    
    @State private var searchText = ""
    
    private var filteredStudents: [CDStudent] {
        let q = searchText.normalizedForComparison()
        let base: [CDStudent]
        if q.isEmpty {
            base = students
        } else {
            base = students.filter { s in
                let f = s.firstName.lowercased()
                let l = s.lastName.lowercased()
                let full = s.fullName.lowercased()
                return f.contains(q) || l.contains(q) || full.contains(q)
            }
        }
        return base.sorted { lhs, rhs in
            let lf = lhs.firstName.localizedCaseInsensitiveCompare(rhs.firstName)
            if lf == .orderedSame {
                return lhs.lastName.localizedCaseInsensitiveCompare(rhs.lastName) == .orderedAscending
            }
            return lf == .orderedAscending
        }
    }
    
    var body: some View {
        VStack(spacing: 10) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search students", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
            )

            Divider().padding(.top, 2)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(filteredStudents, id: \.id) { s in
                        let studentID = s.id ?? UUID()
                        Button {
                            if selectedStudentIDs.contains(studentID) {
                                selectedStudentIDs.remove(studentID)
                            } else {
                                selectedStudentIDs.insert(studentID)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: selectedStudentIDs.contains(studentID)
                                    ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(
                                        selectedStudentIDs.contains(studentID)
                                            ? Color.accentColor : Color.secondary
                                    )
                                Text(displayName(s))
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 6)
                            .padding(.horizontal, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxHeight: 280)

            Divider()

            HStack {
                Button {
                    selectedStudentIDs = []
                } label: {
                    Text("Clear")
                }
                .buttonStyle(.borderless)

                Spacer()

                Button("Done") {
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(minWidth: 320)
    }
}
