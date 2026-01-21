import SwiftUI
import SwiftData

struct ProjectEditorSheet: View {
    let club: Project?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    @Query(sort: [SortDescriptor(\Student.firstName), SortDescriptor(\Student.lastName)]) private var studentsRaw: [Student]
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    private var students: [Student] { studentsRaw.uniqueByID }

    @State private var title: String = ""
    @State private var bookTitle: String = ""
    @State private var selectedMemberIDs: Set<String> = []

    struct TemplateDraft: Identifiable, Hashable { var id = UUID(); var title: String = ""; var instructions: String = ""; var defaultLinkedLessonID: String? = nil }
    @State private var sharedTemplates: [TemplateDraft] = []

    init(club: Project?) {
        self.club = club
        _title = State(initialValue: club?.title ?? "")
        _bookTitle = State(initialValue: club?.bookTitle ?? "")
        _selectedMemberIDs = State(initialValue: Set(club?.memberStudentIDs ?? []))
        if let club {
            let drafts = (club.sharedTemplates ?? []).filter { $0.isShared }.map { t in TemplateDraft(title: t.title, instructions: t.instructions, defaultLinkedLessonID: t.defaultLinkedLessonID) }
            _sharedTemplates = State(initialValue: drafts.isEmpty ? [TemplateDraft(), TemplateDraft()] : drafts)
        } else {
            _sharedTemplates = State(initialValue: [TemplateDraft(), TemplateDraft()])
        }
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
                            let sid = s.id.uuidString
                            HStack {
                                Toggle(isOn: Binding(get: { selectedMemberIDs.contains(sid) }, set: { v in toggleMember(sid, v) })) {
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
                            TextField("Default Linked Lesson ID (optional)", text: Binding(get: { tpl.defaultLinkedLessonID ?? "" }, set: { tpl.defaultLinkedLessonID = $0.isEmpty ? nil : $0 }))
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

    private var isValid: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func toggleMember(_ id: String, _ add: Bool) {
        if add { selectedMemberIDs.insert(id) } else { _ = selectedMemberIDs.remove(id) }
    }

    private func addTemplate() { if sharedTemplates.count < 2 { sharedTemplates.append(TemplateDraft()) } }
    private func deleteTemplates(at offsets: IndexSet) { sharedTemplates.remove(atOffsets: offsets) }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        let bt = bookTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        if let club {
            // Update existing
            club.title = trimmedTitle
            club.bookTitle = bt.isEmpty ? nil : bt
            club.memberStudentIDs = Array(selectedMemberIDs)

            // Replace shared templates (keep only isShared ones)
            let existingNonShared = (club.sharedTemplates ?? []).filter { !$0.isShared }
            club.sharedTemplates = existingNonShared
            for draft in sharedTemplates.prefix(2) {
                let tpl = ProjectAssignmentTemplate(projectID: club.id, title: draft.title, instructions: draft.instructions, isShared: true, defaultLinkedLessonID: draft.defaultLinkedLessonID)
                club.sharedTemplates = (club.sharedTemplates ?? []) + [tpl]
            }
        } else {
            // Create new
            let newClub = Project(title: trimmedTitle, bookTitle: bt.isEmpty ? nil : bt, memberStudentIDs: Array(selectedMemberIDs))
            // Two shared templates (allow fewer if user left blank; still create placeholders)
            var templates: [ProjectAssignmentTemplate] = []
            for draft in sharedTemplates.prefix(2) {
                let tpl = ProjectAssignmentTemplate(projectID: newClub.id, title: draft.title, instructions: draft.instructions, isShared: true, defaultLinkedLessonID: draft.defaultLinkedLessonID)
                templates.append(tpl)
            }
            newClub.sharedTemplates = templates
            modelContext.insert(newClub)
        }

        _ = saveCoordinator.save(modelContext, reason: "Save Project")
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
