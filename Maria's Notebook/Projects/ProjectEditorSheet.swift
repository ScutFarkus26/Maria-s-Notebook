import SwiftUI
import CoreData

struct ProjectEditorSheet: View {
    let club: CDProject?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    // Test student filtering
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames)
    private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    @FetchRequest(sortDescriptors: CDStudent.sortByName) private var studentsRaw: FetchedResults<CDStudent>
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Filter out test students when setting is disabled
    private var students: [CDStudent] {
        TestStudentsFilter.filterVisible(
            Array(studentsRaw).uniqueByID.filterEnrolled(),
            show: showTestStudents,
            namesRaw: testStudentNamesRaw
        )
    }

    @State private var title: String = ""
    @State private var bookTitle: String = ""
    @State private var selectedMemberIDs: Set<String> = []

    init(club: CDProject?) {
        self.club = club
        _title = State(initialValue: club?.title ?? "")
        _bookTitle = State(initialValue: club?.bookTitle ?? "")
        _selectedMemberIDs = State(initialValue: Set(club?.memberStudentIDsArray ?? []))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(club == nil ? "New Project" : "Edit Project")
                .font(.title2).fontWeight(.semibold)

            Group {
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)
                TextField("Book/Subject (optional)", text: $bookTitle)
                    .textFieldStyle(.roundedBorder)
            }

            // Members
            VStack(alignment: .leading, spacing: 8) {
                Text("Members").font(.headline)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(students) { s in
                            let sid = (s.id ?? UUID()).uuidString
                            HStack {
                                Toggle(isOn: Binding(
                                    get: { selectedMemberIDs.contains(sid) },
                                    set: { v in toggleMember(sid, v) }
                                )) {
                                    Text(StudentFormatter.displayName(for: s))
                                }
                                .toggleStyle(.checkboxOrSwitch)
                            }
                        }
                    }
                }
                .frame(minHeight: 120, maxHeight: 220)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
        }
        .padding(16)
    #if os(macOS)
        .frame(minWidth: 520)
        .presentationSizingFitted()
    #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    #endif
    }

    private var isValid: Bool { !title.trimmed().isEmpty }

    private func toggleMember(_ id: String, _ add: Bool) {
        if add { selectedMemberIDs.insert(id) } else { _ = selectedMemberIDs.remove(id) }
    }

    private func save() {
        let trimmedTitle = title.trimmed()
        guard !trimmedTitle.isEmpty else { return }
        let bt = bookTitle.trimmed()

        if let club {
            // Update existing
            club.title = trimmedTitle
            club.bookTitle = bt.isEmpty ? nil : bt
            club.memberStudentIDsArray = Array(selectedMemberIDs)
        } else {
            // Create new
            let newClub = CDProject(context: modelContext)
            newClub.title = trimmedTitle
            newClub.bookTitle = bt.isEmpty ? nil : bt
            newClub.memberStudentIDsArray = Array(selectedMemberIDs)
        }

        saveCoordinator.save(modelContext, reason: "Save Project")
        dismiss()
    }
}

private extension ToggleStyle where Self == CheckboxOrSwitchToggleStyle {
    static var checkboxOrSwitch: CheckboxOrSwitchToggleStyle { CheckboxOrSwitchToggleStyle() }
}

struct CheckboxOrSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        #if os(macOS)
        Toggle(configuration)
            .toggleStyle(.checkbox)
        #else
        Toggle(configuration)
            .toggleStyle(.switch)
        #endif
    }
}
