import SwiftUI

struct StudentPickerPopover: View {
    let students: [Student]
    @Binding var selectedIDs: Set<UUID>
    var onDone: (() -> Void)? = nil

    @State private var filterLevel: LevelFilter = .all
    @State private var searchText: String = ""
    @State private var showingAddStudent: Bool = false

    @Environment(\.dismiss) private var dismiss

    enum LevelFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case lower = "Lower"
        case upper = "Upper"

        var id: String { rawValue }
    }

    var filteredStudentsForPicker: [Student] {
        let search = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        let searched = students.filter { student in
            if search.isEmpty { return true }
            let first = student.firstName.lowercased()
            let last = student.lastName.lowercased()
            let full = "\(first) \(last)"
            return first.contains(search) || last.contains(search) || full.contains(search)
        }

        let filtered = searched.filter { student in
            switch filterLevel {
            case .all:
                return true
            case .lower:
                return student.level == .lower
            case .upper:
                return student.level == .upper
            }
        }

        return filtered.sorted {
            let leftFirst = $0.firstName.lowercased()
            let rightFirst = $1.firstName.lowercased()
            if leftFirst != rightFirst {
                return leftFirst < rightFirst
            }
            return $0.lastName.lowercased() < $1.lastName.lowercased()
        }
    }

    func displayName(for student: Student) -> String {
        if let first = student.firstName.nonEmpty,
           let last = student.lastName.nonEmpty {
            let initial = last.prefix(1) + "."
            return "\(first) \(initial)"
        } else {
            return student.firstName + student.lastName
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Search…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
#if os(iOS) || os(tvOS) || os(visionOS)
                    .textInputAutocapitalization(.never)
#endif

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Picker("Level", selection: $filterLevel) {
                ForEach(LevelFilter.allCases) { level in
                    Text(level.rawValue).tag(level)
                }
            }
            .pickerStyle(.segmented)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(filteredStudentsForPicker) { student in
                        Button {
                            withAnimation {
                                if selectedIDs.contains(student.id) {
                                    selectedIDs.remove(student.id)
                                } else {
                                    selectedIDs.insert(student.id)
                                }
                            }
                        } label: {
                            HStack {
                                Text(displayName(for: student))
                                    .foregroundColor(.primary)
                                Spacer()
                                if selectedIDs.contains(student.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }

            Divider()

            HStack {
                Button("New Student…") {
                    showingAddStudent = true
                }

                Spacer()

                Button("Done") {
                    if let onDone = onDone {
                        onDone()
                    } else {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(minWidth: 320)
        .sheet(isPresented: $showingAddStudent) {
            AddStudentView()
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
