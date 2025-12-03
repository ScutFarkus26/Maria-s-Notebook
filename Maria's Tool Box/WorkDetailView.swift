import SwiftUI
import SwiftData

fileprivate struct WorkSectionHeader: View {
    let icon: String
    let title: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
        }
    }
}

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

struct WorkDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var lessons: [Lesson]
    @Query private var studentsAll: [Student]
    @Query private var studentLessons: [StudentLesson]
    
    let work: WorkModel
    var onDone: (() -> Void)? = nil
    
    @State private var selectedStudents: Set<UUID>
    @State private var workType: WorkModel.WorkType
    @State private var selectedStudentLessonID: UUID?
    @State private var title: String
    @State private var notes: String
    @State private var showDeleteAlert = false

    @State private var showingStudentPickerPopover = false
    @State private var showingLinkedLessonDetails = false
    @State private var showingBaseLessonDetails = false

    @State private var completedAt: Date?

    @State private var newCheckInDate: Date = Date()
    @State private var newCheckInPurpose: String = ""
    @State private var newCheckInNote: String = ""
    @State private var editingCheckIn: WorkCheckIn? = nil

    init(work: WorkModel, onDone: (() -> Void)? = nil) {
        self.work = work
        self.onDone = onDone
        _selectedStudents = State(initialValue: Set(work.studentIDs))
        _workType = State(initialValue: work.workType)
        _selectedStudentLessonID = State(initialValue: work.studentLessonID)
        _title = State(initialValue: work.title)
        _notes = State(initialValue: work.notes)
        _completedAt = State(initialValue: work.completedAt)
    }
    
    private var lessonsByID: [UUID: Lesson] {
        Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })
    }
    private var studentsByID: [UUID: Student] {
        Dictionary(uniqueKeysWithValues: studentsAll.map { ($0.id, $0) })
    }
    private var studentLessonsByID: [UUID: StudentLesson] {
        Dictionary(uniqueKeysWithValues: studentLessons.map { ($0.id, $0) })
    }
    private var studentLessonSnapshotsByID: [UUID: StudentLessonSnapshot] {
        Dictionary(uniqueKeysWithValues: studentLessonsByID.map { ($0.key, $0.value.snapshot()) })
    }

    private var participantStates: [(student: Student, isDone: Bool)] {
        selectedStudentsList.map { s in
            (student: s, isDone: work.isStudentCompleted(s.id))
        }
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
        let f = student.firstName
        let l = student.lastName
        if !f.isEmpty && !l.isEmpty {
            return "\(f) \(l.prefix(1))."
        }
        return f + (l.isEmpty ? "" : " \(l)")
    }
    
    private var createdAtDateFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }
    
    private var createdDateOnlyFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }

    private var subject: String {
        if let slID = selectedStudentLessonID, let snap = studentLessonSnapshotsByID[slID], let lesson = lessonsByID[snap.lessonID] {
            return lesson.subject
        }
        return ""
    }

    private var subjectColor: Color {
        subject.isEmpty ? .accentColor : AppColors.color(forSubject: subject)
    }

    private var selectedStudentsList: [Student] {
        studentsAll
            .filter { selectedStudents.contains($0.id) }
            .sorted { $0.firstName.localizedCaseInsensitiveCompare($1.firstName) == .orderedAscending }
    }
    
    private var studentLiteList: [StudentLite] {
        selectedStudentsList.map { s in
            StudentLite(id: s.id, name: displayName(for: s))
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 1) Title at the top
                    TextField("Title", text: $title)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: AppTheme.FontSize.titleMedium, weight: .heavy, design: .rounded))
                        .padding(.top, 14)

                    // 2) Students directly under title
                    studentsChipsRow

                    // 3) Linked Lesson next, with 4) Work Type beside if space allows
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            linkedLessonSection
                            workTypeSection
                        }
                        VStack(alignment: .leading, spacing: 16) {
                            linkedLessonSection
                            workTypeSection
                        }
                    }

                    // 5) Per-Student Completion
                    perStudentCompletionSection

                    // 6) Notes
                    notesSection

                    // 7) Check-Ins input box
                    checkInsSection

                    // 8) Overall completion controls
                    completionSection

                    // Created / meta row retained for context
                    metaRow
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
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
            Button("Delete", role: .destructive) { deleteWork() }
            Button("Cancel", role: .cancel) { }
        } message: { Text("This action cannot be undone.") }
        .sheet(isPresented: $showingLinkedLessonDetails) {
            if let slID = selectedStudentLessonID, let sl = studentLessonsByID[slID] {
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
            if let slID = selectedStudentLessonID, let sl = studentLessonsByID[slID], let lesson = lessonsByID[sl.lessonID] {
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
        .sheet(item: $editingCheckIn) { ci in
            WorkCheckInEditSheet(checkIn: ci) {
                editingCheckIn = nil
            }
#if os(macOS)
            .frame(minWidth: 480, minHeight: 260)
            .presentationSizing(.fitted)
#else
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
#endif
        }
        .popover(isPresented: $showingStudentPickerPopover, arrowEdge: .top) {
            StudentPickerPopover(students: studentsAll, selectedIDs: $selectedStudents) {
                showingStudentPickerPopover = false
            }
        }
    }
    
    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Title")
                .font(.system(size: AppTheme.FontSize.caption))
                .foregroundColor(.secondary)
            TextField("Enter a title", text: $title)
                .textFieldStyle(.roundedBorder)
        }
    }
    
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            WorkSectionHeader(icon: "info.circle", title: "Overview")

            if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(title.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: AppTheme.FontSize.titleMedium, weight: .heavy, design: .rounded))
            }
            if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(notes.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: AppTheme.FontSize.titleMedium, weight: .semibold, design: .rounded))
            }
            HStack(spacing: 8) {
                Text("Created:")
                    .font(.system(size: AppTheme.FontSize.caption))
                    .foregroundColor(.secondary)
                Text(createdAtDateFormatter.string(from: work.createdAt))
                    .font(.system(size: AppTheme.FontSize.caption))
                    .foregroundColor(.primary)
                WorkCheckInSummary(work: work)
                    .padding(.leading, 8)
                Spacer()
            }
            if let completedAt {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Completed: \(createdAtDateFormatter.string(from: completedAt))")
                        .font(.system(size: AppTheme.FontSize.caption))
                        .foregroundColor(.primary)
                }
            }

            HStack(alignment: .center, spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(selectedStudentsList, id: \.id) { student in
                            HStack(spacing: 6) {
                                Text(displayName(for: student))
                                    .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                                Button {
                                    selectedStudents.remove(student.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(subjectColor)
                                .accessibilityLabel("Remove \(displayName(for: student))")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .foregroundColor(subjectColor)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(subjectColor.opacity(0.15))
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }

                Spacer(minLength: 0)

                Button {
                    showingStudentPickerPopover = true
                } label: {
                    Label("Manage Students", systemImage: "person.2.badge.plus")
                }
                .buttonStyle(.bordered)
            }
        }
    }
    
    private var workTypeBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(workType.color)
                .frame(width: 10, height: 10)
            Text(workType.title)
                .font(.system(size: AppTheme.FontSize.caption))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(chipBackgroundColor)
        )
    }
    
    private var workTypeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkSectionHeader(icon: "square.grid.2x2", title: "Work Type")
            Picker("Work Type", selection: $workType) {
                ForEach(WorkModel.WorkType.allCases, id: \.self) { type in
                    Text(type.title).tag(type)
                }
            }
            .pickerStyle(.segmented)
        }
    }
    
    private var linkedLessonSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkSectionHeader(icon: "link", title: "Linked Lesson")

            if let slID = selectedStudentLessonID, let snap = studentLessonSnapshotsByID[slID] {
                let lessonName = lessonsByID[snap.lessonID]?.name ?? "Lesson"
                let date = snap.scheduledFor ?? snap.givenAt ?? snap.createdAt
                let label = "\(lessonName) • \(createdDateOnlyFormatter.string(from: date))"
                HStack(spacing: 10) {
                    Button {
                        showingLinkedLessonDetails = true
                    } label: {
                        Label(label, systemImage: "link")
                    }
                    .buttonStyle(.bordered)

                    if lessonsByID[snap.lessonID] != nil {
                        Button {
                            showingBaseLessonDetails = true
                        } label: {
                            Label("Edit Lesson…", systemImage: "pencil")
                        }
                        .buttonStyle(.bordered)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                Text("None")
                    .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var perStudentCompletionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkSectionHeader(icon: "person.2", title: "Per-Student Completion")
            if selectedStudentsList.isEmpty {
                Text("No students selected for this work.")
                    .foregroundStyle(.secondary)
            } else {
                PerStudentCompletionList(
                    workID: work.id,
                    students: studentLiteList
                )
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkSectionHeader(icon: "note.text", title: "Notes")
            TextEditor(text: $notes)
                .frame(minHeight: 100)
                .padding(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(separatorStrokeColor, lineWidth: 1)
                )
        }
    }
    
    private var completionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkSectionHeader(icon: "checkmark.circle", title: "Completion")

            if selectedStudentsList.isEmpty {
                Text("No students selected for this work.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(selectedStudentsList, id: \.id) { student in
                        Toggle(isOn: Binding(
                            get: { work.isStudentCompleted(student.id) },
                            set: { newValue in
                                if newValue {
                                    work.markStudent(student.id, completedAt: Date())
                                } else {
                                    work.markStudent(student.id, completedAt: nil)
                                }
                            }
                        )) {
                            Text(displayName(for: student))
                        }
                    }
                }
            }

            HStack {
                Button(completedAt == nil ? "Mark Work Done" : "Clear Work Done") {
                    if completedAt == nil {
                        completedAt = Date()
                    } else {
                        completedAt = nil
                    }
                }
                .buttonStyle(.borderedProminent)

                Spacer()
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
                saveWork()
            }
            .buttonStyle(.borderedProminent)
            .font(.system(size: AppTheme.FontSize.caption))
            .keyboardShortcut(.defaultAction)
        }
        .padding(.vertical, 8)
    }
    
    private func saveWork() {
        work.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        work.studentIDs = Array(selectedStudents)
        work.workType = workType
        work.studentLessonID = selectedStudentLessonID
        work.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        // Keep participants in sync with selected students
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
    
    private func deleteWork() {
        modelContext.delete(work)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            // Handle save error if needed
        }
    }

    private func addCheckIn() {
        let note = newCheckInNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let purpose = newCheckInPurpose.trimmingCharacters(in: .whitespacesAndNewlines)
        let ci = WorkCheckIn(workID: work.id, date: newCheckInDate, status: .scheduled, purpose: purpose, note: note, work: work)
        modelContext.insert(ci)
        work.checkIns.append(ci)
        do { try modelContext.save() } catch { }
        newCheckInNote = ""
        newCheckInPurpose = ""
    }

    private func deleteCheckIn(_ ci: WorkCheckIn) {
        if let idx = work.checkIns.firstIndex(where: { $0.id == ci.id }) {
            work.checkIns.remove(at: idx)
        }
        modelContext.delete(ci)
        do { try modelContext.save() } catch { }
    }

    private var studentsChipsRow: some View {
        HStack(alignment: .center, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(selectedStudentsList, id: \.id) { student in
                        HStack(spacing: 6) {
                            Text(displayName(for: student))
                                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                            Button {
                                selectedStudents.remove(student.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(subjectColor)
                            .accessibilityLabel("Remove \(displayName(for: student))")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundColor(subjectColor)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(subjectColor.opacity(0.15))
                        )
                    }
                }
                .padding(.vertical, 2)
            }

            Spacer(minLength: 0)

            Button { showingStudentPickerPopover = true } label: {
                Label("Manage Students", systemImage: "person.2.badge.plus")
            }
            .buttonStyle(.bordered)
        }
    }

    private var metaRow: some View {
        HStack(spacing: 8) {
            Text("Created:")
                .font(.system(size: AppTheme.FontSize.caption))
                .foregroundColor(.secondary)
            Text(createdAtDateFormatter.string(from: work.createdAt))
                .font(.system(size: AppTheme.FontSize.caption))
                .foregroundColor(.primary)
            Spacer()
        }
    }

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
                        addCheckIn()
                    } label: {
                        Label("Add Check-In", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
            }

            // Existing check-ins list
            let items = work.checkIns.sorted(by: { $0.date > $1.date })
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
                                    var c = ci; c.status = .completed; do { try modelContext.save() } catch { }
                                } label: { Label("Mark Completed", systemImage: "checkmark.circle") }
                                Button {
                                    var c = ci; c.status = .scheduled; do { try modelContext.save() } catch { }
                                } label: { Label("Mark Scheduled", systemImage: "clock") }
                                Button {
                                    var c = ci; c.status = .skipped; do { try modelContext.save() } catch { }
                                } label: { Label("Mark Skipped", systemImage: "xmark.circle") }
                                Divider()
                                Button {
                                    editingCheckIn = ci
                                } label: { Label("Edit…", systemImage: "pencil") }
                                Divider()
                                Button(role: .destructive) { deleteCheckIn(ci) } label: { Label("Delete", systemImage: "trash") }
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
}

private struct WorkCheckInEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let checkIn: WorkCheckIn
    var onDone: (() -> Void)? = nil

    @State private var date: Date
    @State private var status: WorkCheckInStatus
    @State private var purpose: String
    @State private var note: String

    init(checkIn: WorkCheckIn, onDone: (() -> Void)? = nil) {
        self.checkIn = checkIn
        self.onDone = onDone
        _date = State(initialValue: checkIn.date)
        _status = State(initialValue: checkIn.status)
        _purpose = State(initialValue: checkIn.purpose)
        _note = State(initialValue: checkIn.note)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Check-In")
                .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))

            HStack(spacing: 12) {
                DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
#if os(macOS)
                    .datePickerStyle(.field)
#endif
                Picker("Status", selection: $status) {
                    ForEach(WorkCheckInStatus.allCases, id: \.self) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.menu)
                TextField("Purpose", text: $purpose)
                    .textFieldStyle(.roundedBorder)
            }

            TextField("Notes (optional)", text: $note)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") {
                    if let onDone { onDone() } else { dismiss() }
                }
                Button("Save") {
                    checkIn.date = date
                    checkIn.status = status
                    checkIn.purpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
                    checkIn.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
                    do { try modelContext.save() } catch { }
                    if let onDone { onDone() } else { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }
}

#Preview {
    // Requires real model data for meaningful preview.
    Text("WorkDetailView requires real model data for preview")
}
