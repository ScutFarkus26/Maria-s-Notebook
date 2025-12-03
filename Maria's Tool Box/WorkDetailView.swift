import SwiftUI
import SwiftData
import Combine

private extension WorkModel.WorkType {
    var title: String { self.rawValue }
    var color: Color {
        switch self {
        case .research: return .teal
        case .followUp: return .orange
        case .practice: return .purple
        }
    }
}

final class WorkDetailViewModel: ObservableObject {
    @Published var selectedStudentIDs: Set<UUID>
    @Published var workType: WorkModel.WorkType
    @Published var selectedStudentLessonID: UUID?
    @Published var title: String
    @Published var notes: String
    @Published var completedAt: Date?

    @Published var checkIns: [WorkCheckIn]

    // Caches
    @Published private(set) var lessonsByID: [UUID: Lesson] = [:]
    @Published private(set) var studentsByID: [UUID: Student] = [:]
    @Published private(set) var studentLessonsByID: [UUID: StudentLesson] = [:]
    @Published private(set) var studentLessonSnapshotsByID: [UUID: StudentLessonSnapshot] = [:]

    let work: WorkModel
    var onDone: (() -> Void)? = nil

    init(work: WorkModel, onDone: (() -> Void)? = nil) {
        self.work = work
        self.onDone = onDone
        self.selectedStudentIDs = Set(work.studentIDs)
        self.workType = work.workType
        self.selectedStudentLessonID = work.studentLessonID
        self.title = work.title
        self.notes = work.notes
        self.completedAt = work.completedAt
        self.checkIns = work.checkIns
    }

    func rebuildCaches(lessons: [Lesson], students: [Student], studentLessons: [StudentLesson]) {
        lessonsByID = Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })
        studentsByID = Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) })
        studentLessonsByID = Dictionary(uniqueKeysWithValues: studentLessons.map { ($0.id, $0) })
        studentLessonSnapshotsByID = Dictionary(uniqueKeysWithValues: studentLessonsByID.map { ($0.key, $0.value.snapshot()) })
    }

    var selectedStudentsList: [Student] {
        studentsByID.values
            .filter { selectedStudentIDs.contains($0.id) }
            .sorted { $0.firstName.localizedCaseInsensitiveCompare($1.firstName) == .orderedAscending }
    }

    var studentLiteList: [StudentLite] {
        selectedStudentsList.map { s in
            StudentLite(id: s.id, name: displayName(for: s))
        }
    }

    private func displayName(for student: Student) -> String {
        let f = student.firstName
        let l = student.lastName
        if !f.isEmpty && !l.isEmpty {
            return "\(f) \(l.prefix(1))."
        }
        return f + (l.isEmpty ? "" : " \(l)")
    }

    func isStudentCompletedDraft(_ studentID: UUID) -> Bool {
        work.isStudentCompleted(studentID)
    }

    func setStudentCompletedDraft(_ studentID: UUID, _ completed: Bool) {
        if completed {
            work.markStudent(studentID, completedAt: Date())
        } else {
            work.markStudent(studentID, completedAt: nil)
        }
    }

    func addCheckInDraft(date: Date, purpose: String, note: String, modelContext: ModelContext? = nil) {
        let trimmedPurpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let ci = WorkCheckIn(workID: work.id, date: date, status: .scheduled, purpose: trimmedPurpose, note: trimmedNote, work: work)
        checkIns.append(ci)
        work.checkIns.append(ci)
        modelContext?.insert(ci)
        do {
            try modelContext?.save()
        } catch { }
    }

    func setCheckInDraftStatus(_ id: UUID, to status: WorkCheckInStatus, modelContext: ModelContext? = nil) {
        guard let index = checkIns.firstIndex(where: { $0.id == id }) else { return }
        checkIns[index].status = status
        do {
            try modelContext?.save()
        } catch { }
    }

    func deleteCheckInDraft(_ ci: WorkCheckIn, modelContext: ModelContext? = nil) {
        if let idx = checkIns.firstIndex(where: { $0.id == ci.id }) {
            checkIns.remove(at: idx)
        }
        work.checkIns.removeAll(where: { $0.id == ci.id })
        modelContext?.delete(ci)
        do {
            try modelContext?.save()
        } catch { }
    }

    var subject: String {
        if let slID = selectedStudentLessonID,
           let snap = studentLessonSnapshotsByID[slID],
           let lesson = lessonsByID[snap.lessonID] {
            return lesson.subject
        }
        return ""
    }

    var subjectColor: Color {
        subject.isEmpty ? .accentColor : AppColors.color(forSubject: subject)
    }

    func save(modelContext: ModelContext, dismiss: @escaping () -> Void) {
        work.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        work.studentIDs = Array(selectedStudentIDs)
        work.workType = workType
        work.studentLessonID = selectedStudentLessonID
        work.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        work.ensureParticipantsFromStudentIDs()
        work.completedAt = completedAt
        do {
            try modelContext.save()
            if let onDone = onDone {
                onDone()
            } else {
                dismiss()
            }
        } catch {
            // Handle save error if needed
        }
    }

    func deleteWork(modelContext: ModelContext, dismiss: @escaping () -> Void) {
        modelContext.delete(work)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            // Handle save error if needed
        }
    }
    
    // Added for phase 3 editing of check-in drafts:
    struct CheckInDraft: Identifiable, Equatable {
        var id: UUID
        var date: Date
        var status: WorkCheckInStatus
        var purpose: String
        var note: String
    }
    
    func updateCheckInDraft(_ draft: CheckInDraft) {
        guard let idx = checkIns.firstIndex(where: { $0.id == draft.id }) else { return }
        checkIns[idx].date = draft.date
        checkIns[idx].status = draft.status
        checkIns[idx].purpose = draft.purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        checkIns[idx].note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var checkInDrafts: [CheckInDraft] {
        checkIns.map { ci in
            CheckInDraft(id: ci.id, date: ci.date, status: ci.status, purpose: ci.purpose, note: ci.note)
        }
    }
}

struct WorkDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var lessons: [Lesson]
    @Query private var studentsAll: [Student]
    @Query private var studentLessons: [StudentLesson]

    @StateObject private var vm: WorkDetailViewModel

    @State private var newCheckInDate: Date = Date()
    @State private var newCheckInPurpose: String = ""
    @State private var newCheckInNote: String = ""
    
    // 1) Add new state for editing check-in drafts:
    @State private var editingCheckInDraft: WorkDetailViewModel.CheckInDraft? = nil

    let work: WorkModel
    var onDone: (() -> Void)? = nil

    init(work: WorkModel, onDone: (() -> Void)? = nil) {
        self.work = work
        self.onDone = onDone
        _vm = StateObject(wrappedValue: WorkDetailViewModel(work: work, onDone: onDone))
    }

    private static let createdDateTimeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    private static let createdDateOnlyFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()

    private var selectedStudentsList: [Student] {
        studentsAll
            .filter { vm.selectedStudentIDs.contains($0.id) }
            .sorted { $0.firstName.localizedCaseInsensitiveCompare($1.firstName) == .orderedAscending }
    }

    private var subject: String {
        if let slID = vm.selectedStudentLessonID,
           let snap = vm.studentLessonSnapshotsByID[slID],
           let lesson = vm.lessonsByID[snap.lessonID] {
            return lesson.subject
        }
        return ""
    }

    private var subjectColor: Color {
        subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .accentColor : AppColors.color(forSubject: subject)
    }

    private var chipBackgroundColor: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }

    private var separatorStrokeColor: Color {
        #if os(macOS)
        return Color.primary.opacity(0.12)
        #else
        return Color(uiColor: .separator)
        #endif
    }

    private func displayName(for student: Student) -> String {
        selectedStudentsList.first(where: { $0.id == student.id }).map { s in
            let f = s.firstName
            let l = s.lastName
            if !f.isEmpty && !l.isEmpty {
                return "\(f) \(l.prefix(1))."
            }
            return f + (l.isEmpty ? "" : " \(l)")
        } ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 1) Title at the top
                    TextField("Title", text: $vm.title)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: AppTheme.FontSize.titleMedium, weight: .heavy, design: .rounded))
                        .padding(.top, 14)

                    // 2) Students directly under title
                    StudentsChipsRow(students: studentsAll, selectedIDs: $vm.selectedStudentIDs, subjectColor: subjectColor) {
                        showingStudentPickerPopover = true
                    }

                    // 3) Linked Lesson next, with 4) Work Type beside if space allows
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            LinkedLessonSection(
                                lessonsByID: vm.lessonsByID,
                                studentLessonSnapshotsByID: vm.studentLessonSnapshotsByID,
                                selectedStudentLessonID: $vm.selectedStudentLessonID,
                                createdDateOnlyFormatter: Self.createdDateOnlyFormatter,
                                onOpenLinkedDetails: { showingLinkedLessonDetails = true },
                                onOpenBaseLesson: { showingBaseLessonDetails = true }
                            )
                            WorkTypePickerSection(workType: $vm.workType)
                        }
                        VStack(alignment: .leading, spacing: 16) {
                            LinkedLessonSection(
                                lessonsByID: vm.lessonsByID,
                                studentLessonSnapshotsByID: vm.studentLessonSnapshotsByID,
                                selectedStudentLessonID: $vm.selectedStudentLessonID,
                                createdDateOnlyFormatter: Self.createdDateOnlyFormatter,
                                onOpenLinkedDetails: { showingLinkedLessonDetails = true },
                                onOpenBaseLesson: { showingBaseLessonDetails = true }
                            )
                            WorkTypePickerSection(workType: $vm.workType)
                        }
                    }

                    // 5) Per-Student Completion
                    perStudentCompletionSection

                    // 6) Notes
                    NotesSection(notes: $vm.notes, separatorStrokeColor: separatorStrokeColor)

                    // 7) Check-Ins input box
                    checkInsSection

                    // 8) Created / meta row retained for context
                    metaRow
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
                .onAppear {
                    vm.rebuildCaches(lessons: lessons, students: studentsAll, studentLessons: studentLessons)
                }
                .onChange(of: lessons.map(\.id)) { _, _ in
                    vm.rebuildCaches(lessons: lessons, students: studentsAll, studentLessons: studentLessons)
                }
                .onChange(of: studentsAll.map(\.id)) { _, _ in
                    vm.rebuildCaches(lessons: lessons, students: studentsAll, studentLessons: studentLessons)
                }
                .onChange(of: studentLessons.map(\.id)) { _, _ in
                    vm.rebuildCaches(lessons: lessons, students: studentsAll, studentLessons: studentLessons)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar
                .background(.ultraThinMaterial)
                .padding(.top, 6)
                .padding(.horizontal)
                .padding(.bottom, 10)
        }
        .alert("Delete Work?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                vm.deleteWork(modelContext: modelContext) {
                    if let onDone = onDone {
                        onDone()
                    } else {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(isPresented: $showingLinkedLessonDetails) {
            if let slID = vm.selectedStudentLessonID, let sl = vm.studentLessonsByID[slID] {
                StudentLessonDetailView(studentLesson: sl) { showingLinkedLessonDetails = false }
#if os(macOS)
                .frame(minWidth: 520, minHeight: 560)
                .presentationSizing(.fitted)
#else
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .padding(.bottom, 16)
#endif
            } else { EmptyView() }
        }
        .sheet(isPresented: $showingBaseLessonDetails) {
            if let slID = vm.selectedStudentLessonID,
               let sl = vm.studentLessonsByID[slID],
               let lesson = vm.lessonsByID[sl.lessonID] {
                LessonDetailView(lesson: lesson, onSave: { _ in
                    do { try modelContext.save() } catch { }
                }, onDone: { showingBaseLessonDetails = false })
#if os(macOS)
                .frame(minWidth: 520, minHeight: 560)
                .presentationSizing(.fitted)
#else
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .padding(.bottom, 16)
#endif
            } else { EmptyView() }
        }
        .popover(isPresented: $showingStudentPickerPopover, arrowEdge: .top) {
            StudentPickerPopover(students: studentsAll, selectedIDs: $vm.selectedStudentIDs) {
                showingStudentPickerPopover = false
            }
        }
        // 4) Add sheet to edit a check-in draft:
        .sheet(item: $editingCheckInDraft) { draft in
            VStack(alignment: .leading, spacing: 16) {
                Text("Edit Check-In")
                    .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))

                HStack(spacing: 12) {
                    DatePicker("Date", selection: .init(get: { draft.date }, set: { editingCheckInDraft?.date = $0 }), displayedComponents: [.date, .hourAndMinute])
#if os(macOS)
                    .datePickerStyle(.field)
#endif
                    Picker("Status", selection: .init(get: { draft.status }, set: { editingCheckInDraft?.status = $0 })) {
                        ForEach(WorkCheckInStatus.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.menu)
                    TextField("Purpose", text: .init(get: { draft.purpose }, set: { editingCheckInDraft?.purpose = $0 }))
                        .textFieldStyle(.roundedBorder)
                }

                TextField("Notes (optional)", text: .init(get: { draft.note }, set: { editingCheckInDraft?.note = $0 }))
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Spacer()
                    Button("Cancel") { editingCheckInDraft = nil }
                    Button("Save") {
                        if var updated = editingCheckInDraft { vm.updateCheckInDraft(updated) }
                        editingCheckInDraft = nil
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
#if os(macOS)
            .frame(minWidth: 480, minHeight: 260)
            .presentationSizing(.fitted)
#else
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
#endif
        }
    }

    @State private var showDeleteAlert = false
    @State private var showingStudentPickerPopover = false
    @State private var showingLinkedLessonDetails = false
    @State private var showingBaseLessonDetails = false

    // 2) Replace perStudentCompletionSection with staged toggles:
    private var perStudentCompletionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkSectionHeader(icon: "person.2", title: "Per-Student Completion")
            if selectedStudentsList.isEmpty {
                Text("No students selected for this work.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(selectedStudentsList, id: \.id) { student in
                        Toggle(isOn: Binding(
                            get: { vm.isStudentCompletedDraft(student.id) },
                            set: { vm.setStudentCompletedDraft(student.id, $0) }
                        )) {
                            Text(displayName(for: student))
                        }
                    }
                }
            }
        }
    }

    // 3) Update checkInsSection with Edit action and use staged API calls:
    private var checkInsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkSectionHeader(icon: "calendar.badge.clock", title: "Check-Ins")

            // Input controls
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    DatePicker("Date", selection: $newCheckInDate, displayedComponents: [.date, .hourAndMinute])
#if os(macOS)
                        .datePickerStyle(.field)
#endif
                    TextField("Purpose", text: $newCheckInPurpose)
                        .textFieldStyle(.roundedBorder)
                }
                TextField("Notes (optional)", text: $newCheckInNote)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button {
                        vm.addCheckInDraft(date: newCheckInDate, purpose: newCheckInPurpose, note: newCheckInNote, modelContext: modelContext)
                        newCheckInNote = ""
                        newCheckInPurpose = ""
                    } label: {
                        Label("Add Check-In", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
            }

            // Existing check-ins list
            let items = vm.checkIns.sorted(by: { $0.date > $1.date })
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items, id: \.id) { ci in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: ci.status == .completed ? "checkmark.circle.fill" : (ci.status == .skipped ? "xmark.circle.fill" : "clock"))
                                .foregroundStyle(ci.status == .completed ? .green : (ci.status == .skipped ? .red : .orange))
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(ci.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                                    let purposeText = ci.purpose.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !purposeText.isEmpty {
                                        Text("•")
                                            .foregroundStyle(.secondary)
                                        Text(purposeText)
                                            .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                                    }
                                }
                                if !ci.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(ci.note)
                                        .font(.system(size: AppTheme.FontSize.caption))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Menu {
                                Button {
                                    editingCheckInDraft = WorkDetailViewModel.CheckInDraft(id: ci.id, date: ci.date, status: ci.status, purpose: ci.purpose, note: ci.note)
                                } label: { Label("Edit…", systemImage: "pencil") }
                                Divider()
                                Button {
                                    vm.setCheckInDraftStatus(ci.id, to: .completed)
                                } label: { Label("Mark Completed", systemImage: "checkmark.circle") }
                                Button {
                                    vm.setCheckInDraftStatus(ci.id, to: .scheduled)
                                } label: { Label("Mark Scheduled", systemImage: "clock") }
                                Button {
                                    vm.setCheckInDraftStatus(ci.id, to: .skipped)
                                } label: { Label("Mark Skipped", systemImage: "xmark.circle") }
                                Divider()
                                Button(role: .destructive) {
                                    vm.deleteCheckInDraft(ci)
                                } label: { Label("Delete", systemImage: "trash") }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                    }
                }
            } else {
                Text("No check-ins yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            Button(role: .destructive) {
                showDeleteAlert = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.system(size: AppTheme.FontSize.caption))
            }

            Spacer()

            Button("Cancel") {
                if let onDone = onDone {
                    onDone()
                } else {
                    dismiss()
                }
            }
            .font(.system(size: AppTheme.FontSize.caption))

            Button("Save") {
                vm.save(modelContext: modelContext) {
                    if let onDone = onDone {
                        onDone()
                    } else {
                        dismiss()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .font(.system(size: AppTheme.FontSize.caption))
            .keyboardShortcut(.defaultAction)
        }
        .padding(.vertical, 8)
    }

    private var metaRow: some View {
        HStack(spacing: 8) {
            Text("Created:")
                .font(.system(size: AppTheme.FontSize.caption))
                .foregroundColor(.secondary)
            Text(Self.createdDateTimeFormatter.string(from: work.createdAt))
                .font(.system(size: AppTheme.FontSize.caption))
                .foregroundColor(.primary)
            Spacer()
        }
    }
}

