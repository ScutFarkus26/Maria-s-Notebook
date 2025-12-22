import SwiftUI
import SwiftData

struct BookClubWeeksEditorView: View {
    let club: BookClub

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    @Query(sort: [SortDescriptor(\BookClubTemplateWeek.weekIndex, order: .forward)]) private var allWeeks: [BookClubTemplateWeek]
    @Query(sort: [SortDescriptor(\BookClubChoiceItem.createdAt, order: .forward)]) private var allChoiceItems: [BookClubChoiceItem]
    @Query(sort: [SortDescriptor(\BookClubChoiceSet.createdAt, order: .forward)]) private var allChoiceSets: [BookClubChoiceSet]
    @Query(sort: [SortDescriptor(\BookClubWeekRoleAssignment.createdAt, order: .forward)]) private var allRoleAssignments: [BookClubWeekRoleAssignment]

    @State private var editingWeek: BookClubTemplateWeek? = nil

    init(club: BookClub) {
        self.club = club
    }

    private var weeks: [BookClubTemplateWeek] {
        allWeeks.filter { $0.bookClubID == club.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Weeks")
                    .font(.headline)
                Spacer()
                Button(action: addWeek) { Label("Add Week", systemImage: "plus") }
            }
            if weeks.isEmpty {
                ContentUnavailableView("No Weeks", systemImage: "calendar", description: Text("Add Week to start building your template."))
            } else {
                List {
                    ForEach(weeks, id: \.id) { week in
                        Button { editingWeek = week } label: {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Week \(week.weekIndex)")
                                        .font(.headline)
                                    if !week.readingRange.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text(week.readingRange)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                HStack(spacing: 8) {
                                    Text("\(choicePromptCountText(for: week))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("\(week.roleAssignments.count) roles assigned")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu { Button("Delete", role: .destructive) { delete(week) } }
                    }
                }
            }
        }
        .sheet(item: $editingWeek) { week in
            BookClubWeekEditorView(club: club, week: week) { editingWeek = nil }
        }
    }

    private func choicePromptCountText(for week: BookClubTemplateWeek) -> String {
        if let setID = week.questionChoiceSetID {
            let items = allChoiceItems.filter { $0.setID == setID }
            let count = items.count
            return "\(count) prompts, pick 2"
        } else {
            return "0 prompts, pick 2"
        }
    }

    private func addWeek() {
        let nextIndex = (weeks.map { $0.weekIndex }.max() ?? 0) + 1
        let w = BookClubTemplateWeek(bookClubID: club.id, weekIndex: nextIndex)
        if w.agendaItems.isEmpty { w.agendaItems = ["Go over work from last week"] }
        modelContext.insert(w)
        _ = saveCoordinator.save(modelContext, reason: "Add book club template week")
        editingWeek = w
    }

    private func delete(_ week: BookClubTemplateWeek) {
        // Delete associated role assignments and choice set/items
        if let setID = week.questionChoiceSetID {
            let items = allChoiceItems.filter { $0.setID == setID }
            for item in items { modelContext.delete(item) }
            if let set = allChoiceSets.first(where: { $0.id == setID }) { modelContext.delete(set) }
        }
        let assigns = allRoleAssignments.filter { $0.weekID == week.id }
        for a in assigns { modelContext.delete(a) }
        modelContext.delete(week)
        _ = saveCoordinator.save(modelContext, reason: "Delete book club template week")
    }
}

struct BookClubWeekEditorView: View, Identifiable {
    var id: UUID { week.id }
    let club: BookClub
    let week: BookClubTemplateWeek
    var onDone: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    @Query(sort: [SortDescriptor(\Student.firstName, order: .forward), SortDescriptor(\Student.lastName, order: .forward)]) private var students: [Student]
    @Query(sort: [SortDescriptor(\BookClubRole.createdAt, order: .forward)]) private var allRoles: [BookClubRole]
    @Query(sort: [SortDescriptor(\BookClubChoiceItem.createdAt, order: .forward)]) private var allChoiceItems: [BookClubChoiceItem]
    @Query(sort: [SortDescriptor(\BookClubWeekRoleAssignment.createdAt, order: .forward)]) private var allRoleAssignments: [BookClubWeekRoleAssignment]
    @Query(sort: [SortDescriptor(\BookClubChoiceSet.createdAt, order: .forward)]) private var allChoiceSets: [BookClubChoiceSet]

    @State private var readingRange: String
    @State private var agenda: [String]
    @State private var vocab: [String]
    @State private var vocabCount: Int

    @State private var choiceItems: [BookClubChoiceItem] = []

    init(club: BookClub, week: BookClubTemplateWeek, onDone: @escaping () -> Void) {
        self.club = club
        self.week = week
        self.onDone = onDone
        _readingRange = State(initialValue: week.readingRange)
        _agenda = State(initialValue: week.agendaItems)
        _vocab = State(initialValue: week.vocabSuggestionWords)
        _vocabCount = State(initialValue: week.vocabRequirementCount)
    }

    private var roles: [BookClubRole] {
        allRoles.filter { $0.bookClubID == club.id }
    }

    private var clubMembers: [Student] {
        let ids = Set(club.memberStudentIDs.compactMap(UUID.init))
        return students.filter { ids.contains($0.id) }.sorted { StudentFormatter.displayName(for: $0) < StudentFormatter.displayName(for: $1) }
    }

    private func loadChoiceItems() {
        if let setID = week.questionChoiceSetID {
            choiceItems = allChoiceItems.filter { $0.setID == setID }
        } else {
            choiceItems = []
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Week \(week.weekIndex)")
                .font(.title3).fontWeight(.semibold)

            Form {
                Section("Reading") {
                    TextField("Reading range (e.g., Chapters 8–14)", text: $readingRange)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Agenda") {
                    editableStringList($agenda, placeholder: "Agenda item")
                }

                Section("Vocabulary suggestions") {
                    editableStringList($vocab, placeholder: "Word")
                    Stepper("Vocabulary requirement count: \(vocabCount)", value: $vocabCount, in: 0...20)
                }

                Section("Weekly Questions (Pick 2 of 3)") {
                    questionsEditor
                }

                Section("Weekly Role Schedule") {
                    if clubMembers.isEmpty {
                        Text("No members in this club.")
                            .foregroundStyle(.secondary)
                    } else if roles.isEmpty {
                        Text("No roles defined. Add roles first.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(clubMembers, id: \.id) { student in
                            HStack {
                                Text(StudentFormatter.displayName(for: student))
                                Spacer()
                                Picker("Role", selection: Binding(
                                    get: { currentRoleID(for: student.id) },
                                    set: { setRoleID($0, for: student.id) }
                                )) {
                                    Text("—").tag(Optional<UUID>(nil))
                                    ForEach(roles, id: \.id) { role in
                                        Text(role.title).tag(Optional(role.id))
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { onDone(); dismiss() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .onAppear { loadChoiceItems() }
    #if os(macOS)
        .frame(minWidth: 640)
        .presentationSizing(.fitted)
    #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    #endif
    }

    // MARK: - Subviews
    private var questionsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Required selections: 2")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { addChoiceItem() } label: { Label("Add", systemImage: "plus") }
                    .disabled(choiceItems.count >= 3)
            }
            ForEach(choiceItems, id: \.id) { item in
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Title", text: Binding(get: { item.title }, set: { item.title = $0 }))
                        .textFieldStyle(.roundedBorder)
                    TextField("Instructions", text: Binding(get: { item.instructions }, set: { item.instructions = $0 }), axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    TextField("Linked Lesson ID (optional)", text: Binding(get: { item.linkedLessonID ?? "" }, set: { item.linkedLessonID = $0.isEmpty ? nil : $0 }))
                        .textFieldStyle(.roundedBorder)
                    HStack { Spacer(); Button("Delete", role: .destructive) { deleteChoiceItem(item) } }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            }
            if choiceItems.count != 3 {
                Text("Guidance: Aim for exactly 3 prompts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func editableStringList(_ binding: Binding<[String]>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(binding.wrappedValue.enumerated()), id: \.offset) { idx, _ in
                HStack {
                    TextField(placeholder, text: Binding(
                        get: { binding.wrappedValue[idx] },
                        set: { binding.wrappedValue[idx] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Button(role: .destructive) { binding.wrappedValue.remove(at: idx) } label: { Image(systemName: "trash") }
                }
            }
            Button { binding.wrappedValue.append("") } label: { Label("Add", systemImage: "plus") }
        }
    }

    // MARK: - Role schedule helpers
    private func currentRoleID(for studentID: UUID) -> UUID? {
        let sid = studentID.uuidString
        return allRoleAssignments.first { $0.weekID == week.id && $0.studentID == sid }?.roleID
    }

    private func setRoleID(_ roleID: UUID?, for studentID: UUID) {
        let sid = studentID.uuidString
        if let existing = allRoleAssignments.first(where: { $0.weekID == week.id && $0.studentID == sid }) {
            if let roleID { existing.roleID = roleID } else { modelContext.delete(existing) }
        } else if let roleID {
            let a = BookClubWeekRoleAssignment(weekID: week.id, studentID: sid, roleID: roleID)
            modelContext.insert(a)
        }
    }

    // MARK: - Choice set helpers
    private func ensureChoiceSet() -> BookClubChoiceSet {
        if let id = week.questionChoiceSetID, let set = allChoiceSets.first(where: { $0.id == id }) {
            return set
        }
        let set = BookClubChoiceSet(bookClubID: club.id, requiredSelectionCount: 2)
        week.questionChoiceSetID = set.id
        modelContext.insert(set)
        return set
    }

    private func addChoiceItem() {
        let set = ensureChoiceSet()
        guard choiceItems.count < 3 else { return }
        let item = BookClubChoiceItem(setID: set.id)
        modelContext.insert(item)
        choiceItems.append(item)
    }

    private func deleteChoiceItem(_ item: BookClubChoiceItem) {
        if let idx = choiceItems.firstIndex(where: { $0.id == item.id }) { choiceItems.remove(at: idx) }
        modelContext.delete(item)
    }

    private func save() {
        week.readingRange = readingRange
        week.agendaItems = agenda
        week.vocabSuggestionWords = vocab
        week.vocabRequirementCount = vocabCount
        // Persist choice set required count = 2 (fixed)
        if let setID = week.questionChoiceSetID, let set = allChoiceSets.first(where: { $0.id == setID }) {
            set.requiredSelectionCount = 2
        }
        _ = saveCoordinator.save(modelContext, reason: "Save book club template week")
        onDone(); dismiss()
    }
}
