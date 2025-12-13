import SwiftUI
import SwiftData
import Combine

struct WorkDetailView: View {
    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar

    // MARK: - Queries
    @Query private var lessons: [Lesson]
    @Query private var studentsAll: [Student]
    @Query private var studentLessons: [StudentLesson]

    // MARK: - View Model
    @StateObject private var vm: WorkDetailViewModel

    // MARK: - UI State
    @State private var checkInDate = Date()
    @State private var checkInPurpose = ""
    @State private var editingCheckInNote: WorkCheckIn?
    @State private var noteText = ""
    @State private var reschedulingCheckIn: WorkCheckIn? = nil
    @State private var rescheduleDate = Date()
    @State private var scheduleNextDate = Date()
    @State private var showScheduleNextSheet = false
    @State private var showDeleteAlert = false
    @State private var showingStudentPickerPopover = false
    @State private var showInlineCheckInComposer = false
    @State private var notesExpanded = false
    @State private var fromLessonExpanded: Bool = false
    @State private var showStudentChips = false
    @State private var rebuildTask: Task<Void, Never>? = nil
    @State private var isDeleting = false
    @State private var selectedNotesStudentID: UUID? = nil

    private enum PresentedSheet: Identifiable {
        case linkedLessonDetails
        case baseLessonDetails
        case studentLessonDraft(UUID)

        var id: String {
            switch self {
            case .linkedLessonDetails: return "linkedLessonDetails"
            case .baseLessonDetails: return "baseLessonDetails"
            case .studentLessonDraft(let id): return "studentLessonDraft_\(id.uuidString)"
            }
        }
    }

    @State private var presentedSheet: PresentedSheet? = nil

    // MARK: - Properties
    let work: WorkModel
    var onDone: (() -> Void)?

    // MARK: - Initialization
    init(work: WorkModel, onDone: (() -> Void)? = nil) {
        self.work = work
        self.onDone = onDone
        _vm = StateObject(wrappedValue: WorkDetailViewModel(work: work, onDone: onDone))
    }

    // MARK: - Date Formatters
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
    
    private static let dateOnlyFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()

    // MARK: - Computed Properties
    private var selectedStudentsList: [Student] { vm.selectedStudentsList }

    private var subjectColor: Color {
        vm.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty 
            ? .accentColor 
            : AppColors.color(forSubject: vm.subject)
    }

    private var sourceLesson: Lesson? {
        return currentLesson
    }

    private var sourceLessonPresentedDate: Date? {
        if let sl = linkedStudentLesson {
            return sl.givenAt ?? sl.scheduledFor ?? sl.createdAt
        }
        return nil
    }

    @MainActor
    private func fromLessonVisibleNotes() -> [Note] {
        guard let lesson = sourceLesson else { return [] }
        let notes: [Note]
        if let sid = selectedNotesStudentID {
            notes = lesson.notesVisible(to: sid)
        } else {
            notes = lesson.notes
        }
        return notes.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.createdAt > rhs.createdAt
        }
    }

    @MainActor
    @ViewBuilder
    private func fromLessonNoteRow(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(scopeText(for: note))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .overlay(
                        Capsule().stroke(Color.primary.opacity(0.12))
                    )
                Spacer()
                HStack(spacing: 2) {
                    Text(note.updatedAt, style: .date)
                    Text(note.updatedAt, style: .time)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Text(note.body)
                .font(.body)
                .foregroundStyle(.primary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    @MainActor
    private func scopeText(for note: Note) -> String {
        switch note.scope {
        case .all: return "All"
        case .student(let id):
            if let s = selectedStudentsList.first(where: { $0.id == id }) {
                return StudentFormatter.displayName(for: s)
            }
            return "Student"
        case .students(let ids):
            return "\(ids.count) students"
        }
    }

    private var availableStudentsForNotes: [Student] {
        selectedStudentsList
    }

    @MainActor
    private var displayedScopedNotes: [Note] {
        if let sid = selectedNotesStudentID {
            return work.notesVisible(to: sid)
        }
        return work.noteItems
    }

    private var linkedStudentLesson: StudentLesson? {
        if let id = vm.selectedStudentLessonID { return vm.studentLessonsByID[id] }
        return nil
    }
    
    private var currentLesson: Lesson? {
        guard let sl = linkedStudentLesson else { return nil }
        return vm.lessonsByID[sl.lessonID]
    }
    
    private var nextLessonInGroupFromWork: Lesson? {
        let actions = StudentLessonDetailActions()
        return actions.nextLessonInGroup(from: currentLesson, lessons: lessons)
    }

    private var separatorStrokeColor: Color {
        #if os(macOS)
        return Color.primary.opacity(0.12)
        #else
        return Color(uiColor: .separator)
        #endif
    }

    // MARK: - Body
    var body: some View {
        Group {
            if isDeleting {
                VStack { ProgressView("Deleting…") }.padding()
            } else {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            titleField
                            studentsArea
                            lessonAndTypeSection
                            nextInGroupSection
                            completionSection
                            splitCompletedButton
                            notesCollapsibleSection
                            scopedNotesSection
                            fromLessonNotesSection
                            checkInsTimelineSection
                            metadataSection
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                        .onAppear { scheduleCacheRebuild() }
                        .onChange(of: lessons.map(\.id)) { 
                            scheduleCacheRebuild()
                        }
                        .onChange(of: studentsAll.map(\.id)) { 
                            scheduleCacheRebuild()
                        }
                        .onChange(of: studentLessons.map(\.id)) { 
                            scheduleCacheRebuild()
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            WorkDetailBottomBar(
                onDelete: { showDeleteAlert = true },
                onCancel: handleCancel,
                onSave: handleSave
            )
            .background(.ultraThinMaterial)
            .padding(.top, 6)
            .padding(.horizontal)
            .padding(.bottom, 10)
        }
        .alert("Delete Work?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive, action: handleDelete)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .linkedLessonDetails:
                linkedLessonSheet
            case .baseLessonDetails:
                baseLessonSheet
            case .studentLessonDraft(let id):
                if let sl = studentLessons.first(where: { $0.id == id }) {
                    StudentLessonDetailView(studentLesson: sl, onDone: {
                        presentedSheet = nil
                    })
                    #if os(macOS)
                    .frame(minWidth: 720, minHeight: 640)
                    .presentationSizing(.fitted)
                    #else
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    #endif
                } else {
                    EmptyView()
                }
            }
        }
        .popover(isPresented: $showingStudentPickerPopover, arrowEdge: .top) {
            StudentPickerPopover(students: studentsAll, selectedIDs: $vm.selectedStudentIDs) {
                showingStudentPickerPopover = false
            }
        }
        .sheet(item: $editingCheckInNote) { checkIn in
            WorkCheckInNoteEditor(
                checkIn: checkIn,
                noteText: $noteText,
                onSave: handleNoteEditorSave,
                onCancel: handleNoteEditorCancel
            )
        }
        .sheet(item: $reschedulingCheckIn) { checkIn in
            VStack(alignment: .leading, spacing: 16) {
                Text("Reschedule Check-In").font(.headline)
                DatePicker("Date", selection: $rescheduleDate, displayedComponents: .date)
                HStack {
                    Spacer()
                    Button("Cancel") { reschedulingCheckIn = nil }
                    Button("Save") {
                        let service = WorkCheckInService(context: modelContext)
                        do { try service.reschedule(checkIn, to: rescheduleDate) } catch { }
                        reschedulingCheckIn = nil
                        updateCaches()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
#if os(macOS)
            .frame(minWidth: 360)
#endif
        }
        .sheet(isPresented: $showScheduleNextSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Schedule Next Lesson").font(.headline)
                DatePicker("Date", selection: $scheduleNextDate, displayedComponents: .date)
                HStack {
                    Spacer()
                    Button("Cancel") { showScheduleNextSheet = false }
                    Button("Schedule") {
                        scheduleNextLessonInGroup(on: scheduleNextDate)
                        showScheduleNextSheet = false
                        updateCaches()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        #if os(macOS)
            .frame(minWidth: 360)
        #endif
        }
    }

    // MARK: - View Sections
    private var titleField: some View {
        TextField("Title", text: $vm.title)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: AppTheme.FontSize.titleMedium, weight: .heavy, design: .rounded))
            .padding(.top, 14)
    }
    
    private var studentsSection: some View {
        StudentsChipsRow(
            students: studentsAll,
            selectedIDs: $vm.selectedStudentIDs,
            subjectColor: subjectColor
        ) {
            showingStudentPickerPopover = true
        }
    }
    
    private var studentsArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "person.2")
                    .foregroundColor(subjectColor)
                Text("\(selectedStudentsList.count) student\(selectedStudentsList.count == 1 ? "" : "s")")
                    .foregroundColor(.primary)
                Spacer()
                Button {
                    showingStudentPickerPopover = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                        showStudentChips.toggle()
                    }
                } label: {
                    Text(showStudentChips ? "Hide" : "Show")
                }
                .buttonStyle(.borderless)
            }
            if showStudentChips {
                studentsSection
            }
        }
    }
    
    private var lessonAndTypeSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                lessonSection
                WorkTypePickerSection(workType: $vm.workType)
            }
            VStack(alignment: .leading, spacing: 16) {
                lessonSection
                WorkTypePickerSection(workType: $vm.workType)
            }
        }
    }

    private var nextInGroupSection: some View {
        Group {
            if let next = nextLessonInGroupFromWork, !vm.selectedStudentIDs.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.right.circle")
                            .foregroundStyle(.blue)
                        Text("Next in Group: \(next.name)")
                            .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
                    }
                    Button {
                        scheduleNextDate = defaultScheduleDate()
                        showScheduleNextSheet = true
                    } label: {
                        Label("Schedule Next in Group", systemImage: "calendar.badge.plus")
                            .font(.system(size: AppTheme.FontSize.callout, design: .rounded))
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
            }
        }
    }
    
    private var lessonSection: some View {
        LinkedLessonSection(
            lessonsByID: vm.lessonsByID,
            studentLessonSnapshotsByID: vm.studentLessonSnapshotsByID,
            selectedStudentLessonID: $vm.selectedStudentLessonID,
            createdDateOnlyFormatter: Self.createdDateOnlyFormatter,
            onOpenLinkedDetails: { presentedSheet = .linkedLessonDetails },
            onOpenBaseLesson: { presentedSheet = .baseLessonDetails },
            selectedStudentIDs: vm.selectedStudentIDs,
            onCreateNewStudentLesson: {
                let newSL = StudentLesson(
                    lesson: nil,
                    students: studentsAll.filter { vm.selectedStudentIDs.contains($0.id) },
                    createdAt: Date(),
                    scheduledFor: nil,
                    givenAt: nil,
                    isPresented: false,
                    notes: "",
                    needsPractice: false,
                    needsAnotherPresentation: false,
                    followUpWork: ""
                )
                newSL.syncSnapshotsFromRelationships()
                modelContext.insert(newSL)
                try? modelContext.save()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    presentedSheet = .studentLessonDraft(newSL.id)
                }
            }
        )
    }
    
    private var completionSection: some View {
        PerStudentCompletionSection(vm: vm)
    }

    @ViewBuilder
    private var splitCompletedButton: some View {
        // Show only for practice work with mixed completion state
        if vm.workType == .practice {
            let completedIDs = Set(work.participants.compactMap { $0.completedAt != nil ? $0.studentID : nil })
            let remainingIDs = Set(work.participants.compactMap { $0.completedAt == nil ? $0.studentID : nil })
            if !completedIDs.isEmpty && !remainingIDs.isEmpty {
                Button {
                    WorkSplitService.splitPracticeWork(work, completedIDs: completedIDs, context: modelContext)
                    // Refresh caches to reflect changes
                    updateCaches()
                } label: {
                    Label("Split Completed", systemImage: "arrow.triangle.branch")
                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                }
                .buttonStyle(.bordered)
                .tint(.purple)
            }
        }
    }
    
    private var notesSection: some View {
        NotesSection(notes: $vm.notes, separatorStrokeColor: separatorStrokeColor)
    }
    
    private var notesCollapsibleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if notesExpanded {
                notesSection
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "note.text")
                        .foregroundColor(.secondary)
                    Text("Notes")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Button("Edit") {
                        withAnimation(.easeInOut) { notesExpanded = true }
                    }
                    .buttonStyle(.borderless)
                }
                Group {
                    if vm.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Add notes…")
                            .foregroundColor(.secondary)
                    } else {
                        Text(vm.notes)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                    }
                }
                .onTapGesture {
                    withAnimation(.easeInOut) { notesExpanded = true }
                }
            }
        }
    }
    
    private var scopedNotesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "note.text")
                    .foregroundColor(.secondary)
                Text("Notes (Scoped)")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Picker("Filter", selection: $selectedNotesStudentID) {
                    Text("All").tag(nil as UUID?)
                    ForEach(selectedStudentsList, id: \.id) { s in
                        Text(StudentFormatter.displayName(for: s)).tag(Optional(s.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 220)
            }
            ScopedNotesSection(
                title: "Notes",
                notes: displayedScopedNotes,
                availableStudents: availableStudentsForNotes,
                defaultScope: .all,
                onAddNote: { body, scope in
                    addScopedNote(body: body, scope: scope)
                }
            )
        }
    }

    private var fromLessonNotesSection: some View {
        Group {
            if let lesson = sourceLesson {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "text.book.closed")
                            .foregroundColor(.secondary)
                        Text("From lesson: \(lesson.name)")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                        if let date = sourceLessonPresentedDate {
                            Text(Self.dateOnlyFormatter.string(from: date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button(fromLessonExpanded ? "Hide" : "Show") {
                            withAnimation(.easeInOut) { fromLessonExpanded.toggle() }
                        }
                        .buttonStyle(.borderless)
                    }
                    if fromLessonExpanded {
                        let notes = fromLessonVisibleNotes()
                        if notes.isEmpty {
                            Text("No notes for this lesson.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(notes, id: \.id) { note in
                                    fromLessonNoteRow(note)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var scheduledCheckInsList: some View {
        ScheduledCheckInsListSection(
            checkIns: vm.checkIns,
            onEditNote: { checkIn in
                noteText = checkIn.note
                editingCheckInNote = checkIn
            },
            onSetStatus: vm.setCheckInDraftStatus,
            onDelete: { vm.deleteCheckInDraft($0, modelContext: modelContext) }
        )
    }
    
    private var scheduleNewCheckInSection: some View {
        ScheduleCheckInSection(
            checkInDate: $checkInDate,
            checkInPurpose: $checkInPurpose
        ) {
            vm.addCheckInDraft(
                date: checkInDate,
                purpose: checkInPurpose,
                note: "",
                modelContext: modelContext
            )
            checkInPurpose = ""
            checkInDate = Date()
        }
    }
    
    private var sortedCheckIns: [WorkCheckIn] {
        vm.checkIns.sorted { $0.date < $1.date }
    }

    private var morningCheckIns: [WorkCheckIn] {
        sortedCheckIns.filter { Calendar.current.component(.hour, from: $0.date) < 12 }
    }

    private var afternoonCheckIns: [WorkCheckIn] {
        sortedCheckIns.filter { Calendar.current.component(.hour, from: $0.date) >= 12 }
    }

    private var checkInsTimelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Check-ins")
                .font(.headline)
                .foregroundColor(.primary)

            if sortedCheckIns.isEmpty {
                inlineCheckInComposer
            } else {
                timelineGroup(title: "Morning", items: morningCheckIns)
                timelineGroup(title: "Afternoon", items: afternoonCheckIns)
                inlineCheckInComposer
            }
        }
    }

    private var metadataSection: some View {
        // Placeholder metadata section. Replace with real details when available.
        EmptyView()
    }

    @ViewBuilder
    private func timelineGroup(title: String, items: [WorkCheckIn]) -> some View {
        if !items.isEmpty {
            HStack {
                Text(title.uppercased())
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                timelineRow(item: item, isLast: index == items.count - 1)
            }
        }
    }

    @ViewBuilder
    private func timelineRow(item: WorkCheckIn, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                Circle()
                    .fill(subjectColor)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(separatorStrokeColor.opacity(0.6), lineWidth: 1)
                    )
                if !isLast {
                    Rectangle()
                        .fill(separatorStrokeColor.opacity(0.4))
                        .frame(width: 1, height: 36)
                }
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(Self.dateOnlyFormatter.string(from: item.date))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(item.purpose)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if !item.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Image(systemName: "text.bubble")
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Menu {
                        Button("Mark Completed", systemImage: "checkmark.circle") {
                            let service = WorkCheckInService(context: modelContext)
                            do { try service.markCompleted(item) } catch { }
                            updateCaches()
                        }
                        Button("Skip", systemImage: "forward.end") {
                            let service = WorkCheckInService(context: modelContext)
                            do { try service.skip(item) } catch { }
                            updateCaches()
                        }
                        Button("Reschedule", systemImage: "calendar") {
                            rescheduleDate = item.date
                            reschedulingCheckIn = item
                        }
                        Divider()
                        Button("Edit Note", systemImage: "square.and.pencil") {
                            noteText = item.note
                            editingCheckInNote = item
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            vm.deleteCheckInDraft(item, modelContext: modelContext)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var inlineCheckInComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut) { showInlineCheckInComposer.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(subjectColor)
                    Text("New check-in (time, purpose)")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if showInlineCheckInComposer {
                VStack(alignment: .leading, spacing: 8) {
                    DatePicker("Date", selection: $checkInDate, displayedComponents: [.date])
                    TextField("Purpose", text: $checkInPurpose)
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: 12) {
                        Button("Add") {
                            vm.addCheckInDraft(
                                date: checkInDate,
                                purpose: checkInPurpose,
                                note: "",
                                modelContext: modelContext
                            )
                            checkInPurpose = ""
                            checkInDate = Date()
                            withAnimation(.easeInOut) { showInlineCheckInComposer = false }
                        }
                        Button("Cancel") {
                            withAnimation(.easeInOut) { showInlineCheckInComposer = false }
                        }
                        .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Sheet Views
    @ViewBuilder
    private var linkedLessonSheet: some View {
        if let slID = vm.selectedStudentLessonID,
           let sl = vm.studentLessonsByID[slID] {
            StudentLessonDetailView(studentLesson: sl, onDone: {
                presentedSheet = nil
            })
            #if os(macOS)
            .frame(minWidth: 520, minHeight: 560)
            .presentationSizing(.fitted)
            #else
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            #endif
        }
    }
    
    @ViewBuilder
    private var baseLessonSheet: some View {
        if let slID = vm.selectedStudentLessonID,
           let sl = vm.studentLessonsByID[slID],
           let lesson = vm.lessonsByID[sl.lessonID] {
            LessonDetailView(lesson: lesson, onSave: { _ in
                Task { @MainActor in
                    try? modelContext.save()
                }
            }, onDone: {
                presentedSheet = nil
            })
            #if os(macOS)
            .frame(minWidth: 520, minHeight: 560)
            .presentationSizing(.fitted)
            #else
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            #endif
        }
    }
    
    // MARK: - Helpers
    private func defaultScheduleDate() -> Date {
        let base = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.startOfDay(for: base)
    }
    
    private func addScopedNote(body: String, scope: NoteScope) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let note = Note(body: trimmed, scope: scope, work: work)
        modelContext.insert(note)
        work.noteItems.append(note)
        do { try modelContext.save() } catch { }
    }

    // MARK: - Actions
    private func scheduleCacheRebuild() {
        // Debounce cache rebuilds to avoid repeated heavy work during rapid updates
        rebuildTask?.cancel()
        rebuildTask = Task { @MainActor in
            // Small delay to coalesce multiple rapid changes
            try? await Task.sleep(nanoseconds: 150_000_000)
            vm.rebuildCaches(
                lessons: lessons,
                students: studentsAll,
                studentLessons: studentLessons
            )
        }
    }

    private func updateCaches() {
        vm.rebuildCaches(
            lessons: lessons,
            students: studentsAll,
            studentLessons: studentLessons
        )
    }
    
    private func handleCancel() {
        if let onDone = onDone {
            onDone()
        } else {
            dismiss()
        }
    }
    
    private func handleSave() {
        vm.save(modelContext: modelContext) {
            if let onDone = onDone {
                onDone()
            } else {
                dismiss()
            }
        }
    }
    
    private func handleDelete() {
        isDeleting = true
        vm.deleteWork(modelContext: modelContext) {
            isDeleting = false
            if let onDone = onDone {
                onDone()
            } else {
                dismiss()
            }
        }
    }
    
    private func handleNoteEditorSave() {
        vm.updateCheckInNote(editingCheckInNote!.id, note: noteText)
        editingCheckInNote = nil
        noteText = ""
    }
    
    private func handleNoteEditorCancel() {
        editingCheckInNote = nil
        noteText = ""
    }

    private func scheduleNextLessonInGroup(on date: Date) {
        guard let next = nextLessonInGroupFromWork else { return }
        let startOfDay = calendar.startOfDay(for: date)
        let scheduled = calendar.date(byAdding: .hour, value: 9, to: startOfDay) ?? startOfDay
        let sameStudents = Set(vm.selectedStudentIDs)
        if let existing = studentLessons.first(where: { $0.resolvedLessonID == next.id && Set($0.resolvedStudentIDs) == sameStudents && $0.givenAt == nil }) {
            existing.setScheduledFor(scheduled, using: calendar)
        } else {
            let newStudentLesson = StudentLesson(
                id: UUID(),
                lessonID: next.id,
                studentIDs: Array(sameStudents),
                createdAt: Date(),
                scheduledFor: scheduled,
                givenAt: nil,
                notes: "",
                needsPractice: false,
                needsAnotherPresentation: false,
                followUpWork: ""
            )
            newStudentLesson.students = studentsAll.filter { sameStudents.contains($0.id) }
            newStudentLesson.lesson = lessons.first(where: { $0.id == next.id })
            modelContext.insert(newStudentLesson)
        }
        do { try modelContext.save() } catch { }
        StudentLessonDetailUtilities.notifyInboxRefresh()
    }
}

