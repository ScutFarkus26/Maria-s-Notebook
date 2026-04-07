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
            Array(studentsRaw).uniqueByID.filter(\.isEnrolled),
            show: showTestStudents,
            namesRaw: testStudentNamesRaw
        )
    }

    @State private var title: String = ""
    @State private var bookTitle: String = ""
    @State private var selectedMemberIDs: Set<String> = []

    struct TemplateDraft: Identifiable, Hashable {
        var id = UUID()
        var title: String = ""
        var instructions: String = ""
        var defaultLinkedLessonID: String?
    }
    @State private var sharedTemplates: [TemplateDraft] = []

    init(club: CDProject?) {
        self.club = club
        _title = State(initialValue: club?.title ?? "")
        _bookTitle = State(initialValue: club?.bookTitle ?? "")
        _selectedMemberIDs = State(initialValue: Set(club?.memberStudentIDsArray ?? []))
        if let club {
            let drafts = ((club.sharedTemplates?.allObjects as? [CDProjectAssignmentTemplate]) ?? [])
                .filter(\.isShared)
                .map { t in
                    TemplateDraft(
                        title: t.title,
                        instructions: t.instructions,
                        defaultLinkedLessonID: t.defaultLinkedLessonID
                    )
                }
            _sharedTemplates = State(initialValue: drafts.isEmpty ? [TemplateDraft(), TemplateDraft()] : drafts)
        } else {
            _sharedTemplates = State(initialValue: [TemplateDraft(), TemplateDraft()])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(club == nil ? "New CDProject" : "Edit CDProject")
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

            // Shared templates (max 2)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Shared Assignments").font(.headline)
                    Spacer()
                    Button(action: addTemplate) { Label("Add", systemImage: "plus") }
                        .disabled(sharedTemplates.count >= 2)
                }
                List {
                    ForEach($sharedTemplates) { $tpl in
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Title", text: $tpl.title)
                            TextField("Instructions", text: $tpl.instructions, axis: .vertical)
                            TextField(
                                "Default Linked Lesson ID (optional)",
                                text: Binding(
                                    get: { tpl.defaultLinkedLessonID ?? "" },
                                    set: { tpl.defaultLinkedLessonID = $0.isEmpty ? nil : $0 }
                                )
                            )
                                .textFieldStyle(.roundedBorder)
                        }
                        .textFieldStyle(.roundedBorder)
                        .padding(.vertical, 4)
                    }
                    .onDelete(perform: deleteTemplates)
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

    private func addTemplate() { if sharedTemplates.count < 2 { sharedTemplates.append(TemplateDraft()) } }
    private func deleteTemplates(at offsets: IndexSet) { sharedTemplates.remove(atOffsets: offsets) }

    private func save() {
        let trimmedTitle = title.trimmed()
        guard !trimmedTitle.isEmpty else { return }
        let bt = bookTitle.trimmed()

        if let club {
            // Update existing
            club.title = trimmedTitle
            club.bookTitle = bt.isEmpty ? nil : bt
            club.memberStudentIDsArray = Array(selectedMemberIDs)

            // Replace shared templates: remove existing shared ones
            let existingTemplates = (club.sharedTemplates?.allObjects as? [CDProjectAssignmentTemplate]) ?? []
            for tpl in existingTemplates where tpl.isShared {
                modelContext.delete(tpl)
            }
            for draft in sharedTemplates.prefix(2) {
                let tpl = CDProjectAssignmentTemplate(context: modelContext)
                tpl.projectID = (club.id ?? UUID()).uuidString
                tpl.title = draft.title
                tpl.instructions = draft.instructions
                tpl.isShared = true
                tpl.defaultLinkedLessonID = draft.defaultLinkedLessonID
                club.addToSharedTemplates(tpl)
            }
        } else {
            // Create new
            let newClub = CDProject(context: modelContext)
            newClub.title = trimmedTitle
            newClub.bookTitle = bt.isEmpty ? nil : bt
            newClub.memberStudentIDsArray = Array(selectedMemberIDs)

            // Two shared templates (allow fewer if user left blank; still create placeholders)
            for draft in sharedTemplates.prefix(2) {
                let tpl = CDProjectAssignmentTemplate(context: modelContext)
                tpl.projectID = (newClub.id ?? UUID()).uuidString
                tpl.title = draft.title
                tpl.instructions = draft.instructions
                tpl.isShared = true
                tpl.defaultLinkedLessonID = draft.defaultLinkedLessonID
                newClub.addToSharedTemplates(tpl)
            }
        }

        saveCoordinator.save(modelContext, reason: "Save CDProject")
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
