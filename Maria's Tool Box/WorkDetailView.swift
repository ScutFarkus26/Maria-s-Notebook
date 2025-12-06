import SwiftUI
import SwiftData
import Combine

struct WorkDetailView: View {
    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
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
    @State private var showDeleteAlert = false
    @State private var showingStudentPickerPopover = false
    @State private var showInlineCheckInComposer = false
    @State private var notesExpanded = false
    @State private var showStudentChips = false
    @State private var rebuildTask: Task<Void, Never>? = nil

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

    private var separatorStrokeColor: Color {
        #if os(macOS)
        return Color.primary.opacity(0.12)
        #else
        return Color(uiColor: .separator)
        #endif
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    titleField
                    studentsArea
                    lessonAndTypeSection
                    completionSection
                    splitCompletedButton
                    notesCollapsibleSection
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
            .padding(.bottom, 16)
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
            .padding(.bottom, 16)
            #endif
        }
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
        vm.deleteWork(modelContext: modelContext) {
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
}

