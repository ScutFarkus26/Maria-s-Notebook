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

    private enum PresentedSheet: Identifiable {
        case linkedLessonDetails
        case baseLessonDetails
        case createStudentLesson

        var id: String {
            switch self {
            case .linkedLessonDetails: return "linkedLessonDetails"
            case .baseLessonDetails: return "baseLessonDetails"
            case .createStudentLesson: return "createStudentLesson"
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

    // MARK: - Computed Properties
    private var selectedStudentsList: [Student] {
        studentsAll
            .filter { vm.selectedStudentIDs.contains($0.id) }
            .sorted { $0.firstName.localizedCaseInsensitiveCompare($1.firstName) == .orderedAscending }
    }

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
                    studentsSection
                    lessonAndTypeSection
                    completionSection
                    notesSection
                    scheduledCheckInsList
                    scheduleNewCheckInSection
                    metadataSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
                .onAppear { updateCaches() }
                .onChange(of: lessons.map(\.id)) { updateCaches() }
                .onChange(of: studentsAll.map(\.id)) { updateCaches() }
                .onChange(of: studentLessons.map(\.id)) { updateCaches() }
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
            case .createStudentLesson:
                GiveLessonSheet(
                    lesson: nil,
                    preselectedStudentIDs: Array(vm.selectedStudentIDs),
                    startGiven: false,
                    allStudents: studentsAll,
                    allLessons: lessons
                ) {
                    presentedSheet = nil
                }
                #if os(macOS)
                .frame(minWidth: 720, minHeight: 640)
                .presentationSizing(.fitted)
                #else
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    presentedSheet = .createStudentLesson
                }
            }
        )
    }
    
    private var completionSection: some View {
        PerStudentCompletionSection(vm: vm)
    }
    
    private var notesSection: some View {
        NotesSection(notes: $vm.notes, separatorStrokeColor: separatorStrokeColor)
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
    
    private var metadataSection: some View {
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
    
    // MARK: - Sheet Views
    @ViewBuilder
    private var linkedLessonSheet: some View {
        if let slID = vm.selectedStudentLessonID,
           let sl = vm.studentLessonsByID[slID] {
            StudentLessonDetailView(studentLesson: sl) {
                presentedSheet = nil
            }
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
                do { try modelContext.save() } catch { }
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

