import SwiftUI

struct PerStudentCompletionSection: View {
    @ObservedObject var vm: WorkDetailViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkSectionHeader(icon: "person.2", title: "Per-Student Completion")
            if vm.selectedStudentsList.isEmpty {
                Text("No students selected for this work.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(vm.selectedStudentsList, id: \.id) { student in
                        Toggle(isOn: Binding(
                            get: { vm.isStudentCompletedDraft(student.id) },
                            set: { vm.setStudentCompletedDraft(student.id, $0) }
                        )) {
                            Text(vm.studentLiteList.first(where: { $0.id == student.id })?.name ?? "")
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    // Minimal preview stub; real data should be provided by the app context.
    PerStudentCompletionSection(vm: WorkDetailViewModel(work: WorkModel(title: "", notes: "", workType: .research, studentIDs: [], studentLessonID: nil)))
}
