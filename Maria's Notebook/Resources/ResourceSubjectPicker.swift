import SwiftUI

/// Multi-select subject picker for linking resources to lesson subjects.
/// Shown as a NavigationLink destination inside import/edit sheets.
struct ResourceSubjectPicker: View {
    let availableSubjects: [String]
    @Binding var selectedSubjects: Set<String>

    var body: some View {
        List {
            if availableSubjects.isEmpty {
                Text("No subjects available yet. Subjects come from your lessons.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                if !selectedSubjects.isEmpty {
                    Section {
                        HStack {
                            Text("\(selectedSubjects.count) subject\(selectedSubjects.count == 1 ? "" : "s") selected")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Clear All") {
                                selectedSubjects.removeAll()
                            }
                            .font(.caption)
                        }
                    }
                }

                Section {
                    ForEach(availableSubjects, id: \.self) { subject in
                        Button {
                            if selectedSubjects.contains(subject) {
                                selectedSubjects.remove(subject)
                            } else {
                                selectedSubjects.insert(subject)
                            }
                        } label: {
                            HStack {
                                Text(subject)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedSubjects.contains(subject) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Link to Subjects")
        .inlineNavigationTitle()
    }
}
