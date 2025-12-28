import SwiftUI

@available(*, deprecated, message: "PerStudentCompletionSection used legacy WorkDetailViewModel. Use WorkContractDetailSheet instead.")
struct PerStudentCompletionSection: View {
    // Deprecated shim: keep previews and any straggler references compiling
    let students: [Student]
    let workID: UUID?
    var isCompleted: (UUID) -> Bool = { _ in false }
    var toggleCompleted: (UUID) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkSectionHeader(icon: "person.2", title: "Per-Student Completion")
            if students.isEmpty {
                Text("No students selected for this work.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(students, id: \.id) { student in
                        Toggle(isOn: Binding(
                            get: { isCompleted(student.id) },
                            set: { _ in toggleCompleted(student.id) }
                        )) {
                            Text(StudentFormatter.displayName(for: student))
                        }
                    }
                }
            }
        }
    }
}

