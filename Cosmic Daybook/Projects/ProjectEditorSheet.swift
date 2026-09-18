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

    @State private var title: String
    @State private var bookTitle: String
    @State private var selectedMemberIDs: Set<String>
    @State private var isActive: Bool
    @State private var isSaving: Bool = false
    @State private var studentSearchText: String = ""

    init(club: CDProject?) {
        self.club = club
        title = club?.title ?? ""
        bookTitle = club?.bookTitle ?? ""
        selectedMemberIDs = Set(club?.memberStudentIDsArray ?? [])
        isActive = club?.isActive ?? true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(club == nil ? "New Project" : "Edit Project")
                .font(.title2).fontWeight(.semibold)

            Group {
                TextField("Project title", text: $title)
                    .textFieldStyle(.roundedBorder)
                TextField("Guiding question or lesson seed", text: $bookTitle)
                    .textFieldStyle(.roundedBorder)
                Toggle("Active project", isOn: $isActive)
                    .toggleStyle(.checkboxOrSwitch)
            }

            // Members
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Students Working on This").font(.headline)
                    Spacer()
                    if !selectedMemberIDs.isEmpty {
                        Text("\(selectedMemberIDs.count) selected")
                            .font(AppTheme.ScaledFont.captionSemibold)
                            .foregroundStyle(.secondary)
                    }
                }

                SearchField("Search students", text: $studentSearchText)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(filteredSelectableStudents, id: \.id) { entry in
                            let s = entry.student
                            let sid = entry.id.uuidString
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

                        if filteredSelectableStudents.isEmpty {
                            Text("No students match this search.")
                                .font(AppTheme.ScaledFont.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, AppTheme.Spacing.small)
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
                    .disabled(!isValid || isSaving)
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

    private var selectableStudents: [(id: UUID, student: CDStudent)] {
        students.compactMap { student in
            guard let id = student.id else { return nil }
            return (id, student)
        }
    }

    private var filteredSelectableStudents: [(id: UUID, student: CDStudent)] {
        let query = studentSearchText.normalizedForComparison()
        guard !query.isEmpty else { return selectableStudents }

        return selectableStudents.filter { entry in
            let student = entry.student
            let values = [
                student.firstName,
                student.lastName,
                student.fullName,
                StudentFormatter.displayName(for: student),
                student.level.rawValue
            ]
            return values.contains { $0.normalizedForComparison().contains(query) }
        }
    }

    private func toggleMember(_ id: String, _ add: Bool) {
        if add { selectedMemberIDs.insert(id) } else { _ = selectedMemberIDs.remove(id) }
    }

    private func save() {
        guard !isSaving else { return }
        let trimmedTitle = title.trimmed()
        guard !trimmedTitle.isEmpty else { return }
        let bt = bookTitle.trimmed()
        let memberIDs = Array(selectedMemberIDs).sorted()
        isSaving = true

        if let club {
            // Update existing
            club.title = trimmedTitle
            club.bookTitle = bt.isEmpty ? nil : bt
            club.memberStudentIDsArray = memberIDs
            club.isActive = isActive
            club.modifiedAt = Date()
        } else {
            // Create new
            let newClub = CDProject(context: modelContext)
            newClub.title = trimmedTitle
            newClub.bookTitle = bt.isEmpty ? nil : bt
            newClub.memberStudentIDsArray = memberIDs
            newClub.isActive = isActive
            newClub.modifiedAt = Date()
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
