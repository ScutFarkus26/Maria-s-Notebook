import SwiftUI
import SwiftData

struct BookClubWeeksEditorView: View {
    let club: BookClub
    let showHeader: Bool

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    @Query(sort: [SortDescriptor<BookClubTemplateWeek>(\.weekIndex, order: .forward)]) private var allWeeks: [BookClubTemplateWeek]
    @Query(sort: [SortDescriptor(\BookClubChoiceItem.createdAt, order: .forward)]) private var allChoiceItems: [BookClubChoiceItem]
    @Query(sort: [SortDescriptor(\BookClubChoiceSet.createdAt, order: .forward)]) private var allChoiceSets: [BookClubChoiceSet]
    @Query(sort: [SortDescriptor(\BookClubWeekRoleAssignment.createdAt, order: .forward)]) private var allRoleAssignments: [BookClubWeekRoleAssignment]

    @State private var editingWeek: BookClubTemplateWeek? = nil

    init(club: BookClub, showHeader: Bool = true) {
        self.club = club
        self.showHeader = showHeader
    }

    private var weeks: [BookClubTemplateWeek] {
        allWeeks.filter { $0.bookClubID == club.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showHeader {
                HStack {
                    Text("Weeks")
                        .font(.headline)
                    Spacer()
                    Button(action: addWeek) { Label("Add Week", systemImage: "plus") }
                }
            } else {
                HStack {
                    Spacer()
                    Button(action: addWeek) { Label("Add Week", systemImage: "plus") }
                }
            }
            if weeks.isEmpty {
                ContentUnavailableView("No Weeks", systemImage: "calendar", description: Text("Add Week to start building your template."))
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(weeks, id: \.id) { week in
                        Button { editingWeek = week } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("Week \(week.weekIndex)")
                                    .font(.body.weight(.semibold))
                                if !week.readingRange.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text("— \(week.readingRange)")
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu { Button("Delete", role: .destructive) { delete(week) } }
                        Divider()
                    }
                }
            }
        }
        .sheet(item: $editingWeek) { week in
            BookClubWeekEditorView(club: club, week: week) { editingWeek = nil }
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
    @Query(sort: [SortDescriptor(\Lesson.name, order: .forward)]) private var allLessons: [Lesson]

    @State private var readingRange: String
    @State private var agenda: [String]
    @State private var vocab: [String]
    @State private var vocabCount: Int
    @State private var linkedLessonID: String?

    @State private var choiceItems: [BookClubChoiceItem] = []
    @State private var pickingLessonForItem: BookClubChoiceItem? = nil
    @State private var pickingLessonForWeek: Bool = false
    @State private var lessonSearchTextByItem: [UUID: String] = [:]

    init(club: BookClub, week: BookClubTemplateWeek, onDone: @escaping () -> Void) {
        self.club = club
        self.week = week
        self.onDone = onDone
        _readingRange = State(initialValue: week.readingRange)
        _agenda = State(initialValue: week.agendaItems)
        _vocab = State(initialValue: week.vocabSuggestionWords)
        _vocabCount = State(initialValue: week.vocabRequirementCount)
        _linkedLessonID = State(initialValue: week.linkedLessonID)
    }

    private var roles: [BookClubRole] {
        allRoles.filter { $0.bookClubID == club.id }
    }

    private var clubMembers: [Student] {
        let ids = Set(club.memberStudentIDs.compactMap(UUID.init))
        return students.filter { ids.contains($0.id) }.sorted { StudentFormatter.displayName(for: $0) < StudentFormatter.displayName(for: $1) }
    }

    private var lessonsByID: [UUID: Lesson] { Dictionary(uniqueKeysWithValues: allLessons.map { ($0.id, $0) }) }

    private func loadChoiceItems() {
        if let setID = week.questionChoiceSetID {
            choiceItems = allChoiceItems.filter { $0.setID == setID }
        } else {
            choiceItems = []
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title
            HStack(alignment: .firstTextBaseline) {
                Text("Week \(week.weekIndex)")
                    .font(.title3).fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sectionCard("Reading & Lesson", systemImage: "book") {
                        TextField("Reading range (e.g., Chapters 8–14)", text: $readingRange)
                            .textFieldStyle(.roundedBorder)
                        
                        Divider().padding(.vertical, 4)
                        
                        HStack {
                            if let lid = linkedLessonID, let uuid = UUID(uuidString: lid), let l = lessonsByID[uuid] {
                                VStack(alignment: .leading) {
                                    Text("Linked Lesson").font(.caption).foregroundStyle(.secondary)
                                    Text(l.name).font(.headline)
                                }
                            } else {
                                Text("No lesson linked for this week")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if linkedLessonID != nil {
                                Button("Clear") { linkedLessonID = nil }
                                    .buttonStyle(.borderless)
                            }
                            Button("Choose Lesson") { pickingLessonForWeek = true }
                                .buttonStyle(.bordered)
                        }
                    }

                    sectionCard("Agenda", systemImage: "list.bullet") {
                        editableStringList($agenda, placeholder: "Agenda item")
                    }

                    sectionCard("Vocabulary", systemImage: "text.book.closed") {
                        editableStringList($vocab, placeholder: "Word")
                        Stepper("Vocabulary requirement count: \(vocabCount)", value: $vocabCount, in: 0...20)
                            .padding(.top, 4)
                    }

                    sectionCard("Weekly Questions (Pick 2 of 3)", systemImage: "questionmark.bubble") {
                        questionsEditor
                    }

                    sectionCard("Weekly Role Schedule", systemImage: "person.2") {
                        if clubMembers.isEmpty {
                            Text("No members in this club.")
                                .foregroundStyle(.secondary)
                        } else if roles.isEmpty {
                            Text("No roles defined. Add roles first.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(clubMembers, id: \.id) { student in
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(StudentFormatter.displayName(for: student))
                                        Spacer(minLength: 12)
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
                                    .padding(.vertical, 4)
                                    Divider()
                                        .opacity(0.15)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }

            Divider()
                .padding(.top, 4)
            // Bottom actions
            HStack {
                Spacer()
                Button("Cancel") { onDone(); dismiss() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
    #if os(macOS)
        .frame(minWidth: 720)
        .presentationSizing(.fitted)
    #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    #endif
        .onAppear { loadChoiceItems() }
        .sheet(item: $pickingLessonForItem) { choiceItem in
            InlineLessonPickerSheet(initialSearch: lessonSearchTextByItem[choiceItem.id] ?? "") { chosenID in
                if let chosenID { choiceItem.linkedLessonID = chosenID.uuidString } else { choiceItem.linkedLessonID = nil }
                _ = saveCoordinator.save(modelContext, reason: "Link weekly question to lesson")
            }
        }
        .sheet(isPresented: $pickingLessonForWeek) {
            InlineLessonPickerSheet(initialSearch: "") { chosenID in
                linkedLessonID = chosenID?.uuidString
            }
        }
    }

    @ViewBuilder
    private func sectionCard<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                Spacer()
            }
            content()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    // MARK: - Subviews
    private var questionsEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Required selections: 2")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { addChoiceItem() } label: { Label("Add", systemImage: "plus") }
                    .disabled(choiceItems.count >= 3)
            }
            ForEach(choiceItems, id: \.id) { item in
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Title", text: Binding(get: { item.title }, set: { item.title = $0 }))
                        .textFieldStyle(.roundedBorder)
                    TextEditor(text: Binding(get: { item.instructions }, set: { item.instructions = $0 }))
                        .frame(minHeight: 96)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.25))
                        )
                    HStack(spacing: 8) {
                        if let lid = item.linkedLessonID, let uuid = UUID(uuidString: lid), let lesson = lessonsByID[uuid] {
                            Text("Linked: \(lesson.name)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No lesson linked")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        TextField("Search lessons…", text: Binding(
                            get: { lessonSearchTextByItem[item.id] ?? "" },
                            set: { lessonSearchTextByItem[item.id] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                        .onChange(of: lessonSearchTextByItem[item.id] ?? "") { _, newValue in
                            if pickingLessonForItem == nil && !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                pickingLessonForItem = item
                            }
                        }
                        Spacer()
                        Button {
                            pickingLessonForItem = item
                        } label: {
                            Label("Choose Lesson", systemImage: "book")
                        }
                        if item.linkedLessonID != nil {
                            Button("Clear") { item.linkedLessonID = nil }
                                .buttonStyle(.borderless)
                        }
                    }
                    HStack { Spacer(); Button("Delete", role: .destructive) { deleteChoiceItem(item) } }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.03)))
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
                        .buttonStyle(.borderless)
                }
            }
            Button { binding.wrappedValue.append("") } label: { Label("Add", systemImage: "plus") }
                .buttonStyle(.bordered)
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
        week.linkedLessonID = linkedLessonID
        // Persist choice set required count = 2 (fixed)
        if let setID = week.questionChoiceSetID, let set = allChoiceSets.first(where: { $0.id == setID }) {
            set.requiredSelectionCount = 2
        }
        _ = saveCoordinator.save(modelContext, reason: "Save book club template week")
        onDone(); dismiss()
    }
}

private struct InlineLessonPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var search: String = ""
    @Query(sort: [SortDescriptor(\Lesson.name, order: .forward)]) private var lessons: [Lesson]
    var initialSearch: String = ""
    var onChosen: (UUID?) -> Void

    init(initialSearch: String = "", onChosen: @escaping (UUID?) -> Void) {
        self.initialSearch = initialSearch
        self.onChosen = onChosen
        _search = State(initialValue: initialSearch)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Lesson")
                .font(.title3).fontWeight(.semibold)
            TextField("Search…", text: $search)
                .textFieldStyle(.roundedBorder)
            List {
                ForEach(filteredLessons) { lesson in
                    Button {
                        onChosen(lesson.id)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lesson.name.isEmpty ? "Untitled Lesson" : lesson.name)
                                let subtitle: String = {
                                    switch (lesson.subject.isEmpty, lesson.group.isEmpty) {
                                    case (false, false): return "\(lesson.subject) • \(lesson.group)"
                                    case (false, true): return lesson.subject
                                    case (true, false): return lesson.group
                                    default: return ""
                                    }
                                }()
                                if !subtitle.isEmpty {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
            }
        }
        .padding(16)
    #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    #endif
        .onAppear {
            // Fix: ensure state matches passed-in search, in case View identity was recycled
            search = initialSearch
        }
    }

    private var filteredLessons: [Lesson] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return lessons }
        return lessons.filter { l in
            l.name.localizedCaseInsensitiveContains(q) ||
            l.subject.localizedCaseInsensitiveContains(q) ||
            l.group.localizedCaseInsensitiveContains(q)
        }
    }
}
