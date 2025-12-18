import SwiftUI
import SwiftData

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct StudentLessonDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @AppStorage("useEngagementLifecycle") private var useEngagementLifecycle: Bool = false
    @Query private var lessons: [Lesson]
    @Query private var studentsAll: [Student]
    @Query private var studentLessonsAll: [StudentLesson]
    @Query private var workModels: [WorkModel]

    let studentLesson: StudentLesson
    let autoFocusLessonPicker: Bool
    var onDone: (() -> Void)? = nil

    // Local editing state (not saved until user clicks Save)
    @State private var editingLessonID: UUID
    @State private var scheduledFor: Date?
    @State private var givenAt: Date?
    @State private var isPresented: Bool
    @State private var notes: String
    @State private var needsAnotherPresentation: Bool
    @State private var showFollowUpSheet: Bool = false
    @State private var followUpDraft: String = ""

    @StateObject private var lessonPickerVM: LessonPickerViewModel
    @State private var lessonPickerFocused: Bool = false

    @State private var selectedStudentIDs: Set<UUID> = []
    @State private var showingAddStudentSheet = false
    @State private var showingStudentPickerPopover = false
    @State private var showDeleteAlert: Bool = false

    @State private var showingMoveStudentsSheet = false
    @State private var studentsToMove: Set<UUID> = []
    @State private var showMovedBanner: Bool = false
    @State private var movedStudentNames: [String] = []

    @State private var showLessonPicker: Bool = false
    @StateObject private var vm = StudentLessonDetailActions()

    init(studentLesson: StudentLesson, onDone: (() -> Void)? = nil, autoFocusLessonPicker: Bool = false) {
        self.studentLesson = studentLesson
        self.onDone = onDone
        self.autoFocusLessonPicker = autoFocusLessonPicker
        
        // Initialize local editing state from the student lesson
        _editingLessonID = State(initialValue: studentLesson.lessonID)
        _scheduledFor = State(initialValue: studentLesson.scheduledFor)
        _givenAt = State(initialValue: studentLesson.givenAt)
        _isPresented = State(initialValue: studentLesson.isPresented)
        _notes = State(initialValue: studentLesson.notes)
        _needsAnotherPresentation = State(initialValue: studentLesson.needsAnotherPresentation)
        _selectedStudentIDs = State(initialValue: Set(studentLesson.studentIDs))
        
        _lessonPickerVM = StateObject(wrappedValue: LessonPickerViewModel(selectedStudentIDs: [], selectedLessonID: studentLesson.lessonID))
        // Show picker initially if auto-focus is requested
        _showLessonPicker = State(initialValue: autoFocusLessonPicker)
    }

    private var resolvedPickerLesson: Lesson? { lessons.first(where: { $0.id == lessonPickerVM.selectedLessonID }) ?? lessonObject }

    private var lessonObject: Lesson? {
        lessons.first(where: { $0.id == editingLessonID })
    }

    private var lessonName: String {
        lessonObject?.name ?? "Lesson"
    }

    private var subject: String {
        lessonObject?.subject ?? ""
    }

    private var subjectColor: Color {
        AppColors.color(forSubject: subject)
    }

    private var nextLessonInGroup: Lesson? {
        guard let current = lessonObject else { return nil }
        return vm.nextLessonInGroup(from: current, lessons: lessons)
    }

    private func resolveLessonPagesURL() -> URL? {
        guard let lesson = lessonObject else { return nil }
        // Prefer relative path inside managed container
        if let rel = lesson.pagesFileRelativePath, !rel.isEmpty, let url = try? LessonFileStorage.resolve(relativePath: rel) {
            return url
        }
        // Fallback to legacy bookmark
        guard let bookmark = lesson.pagesFileBookmark else { return nil }
        var stale = false
        do {
#if os(macOS)
            let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
#else
            let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
#endif
            _ = url.startAccessingSecurityScopedResource()
            return url
        } catch {
            return nil
        }
    }
    
    private func openInPages(_ url: URL) {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
#if os(iOS)
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
#elseif os(macOS)
        if let pagesAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iWork.Pages") {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open([url], withApplicationAt: pagesAppURL, configuration: config, completionHandler: nil)
        } else {
            NSWorkspace.shared.open(url)
        }
#endif
    }

    private var selectedStudentsList: [Student] {
        studentsAll
            .filter { selectedStudentIDs.contains($0.id) }
            .sorted { $0.firstName.localizedCaseInsensitiveCompare($1.firstName) == .orderedAscending }
    }
    
    // MARK: - New Redesigned Sections
    
    /// 1. Lesson Header: Large title + subject/category pills
    private var lessonHeaderSection: some View {
        let hasFile: Bool = {
            if let lesson = lessonObject {
                if let rel = lesson.pagesFileRelativePath, !rel.isEmpty { return true }
                if lesson.pagesFileBookmark != nil { return true }
            }
            return false
        }()
        return StudentLessonHeaderView(
            lessonName: lessonName,
            subject: lessonObject?.subject ?? "",
            group: lessonObject?.group ?? "",
            subjectColor: subjectColor,
            onTapTitle: hasFile ? { if let url = resolveLessonPagesURL() { openInPages(url) } } : nil
        )
    }
    
    /// 3. Student Pills + Add/Remove (replaced with extracted view)
    private var studentPillsSection: some View {
        StudentPillsSection(
            students: selectedStudentsList,
            subjectColor: subjectColor,
            onRemove: { id in selectedStudentIDs.remove(id) },
            onOpenPicker: { showingStudentPickerPopover = true },
            onOpenMove: {
                studentsToMove = []
                showingMoveStudentsSheet = true
            },
            canMoveStudents: selectedStudentsList.count > 1 && !isPresented
        )
        .popover(isPresented: $showingStudentPickerPopover, arrowEdge: .top) {
            StudentPickerPopover(
                students: studentsAll,
                selectedIDs: $selectedStudentIDs,
                onDone: { showingStudentPickerPopover = false }
            )
            .padding(12)
            .frame(minWidth: 320)
        }
    }
    
    /// 4. Inbox/Scheduling Status (replaced with extracted view)
    private var inboxStatusSection: some View {
        InboxStatusSection(scheduledFor: $scheduledFor)
    }
    
    /// 7. Notes Section with subtle ruled-paper aesthetic (replaced with extracted view)
    private var notesSection: some View { NotesSectionView(notes: $notes) }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    // 1. Lesson Title & Tags Header
                    lessonHeaderSection
                        .padding(.horizontal, 32)
                        .padding(.top, 32)
                    
                    // 2. Conditional Lesson Picker (only when not selected or user wants to change)
                    if lessonObject == nil || showLessonPicker {
                        lessonPickerSection
                            .padding(.horizontal, 32)
                            .padding(.top, 16)
                    } else {
                        // Use ChangeLessonControl instead of manual "Change Lesson" button
                        ChangeLessonControl(showLessonPicker: $showLessonPicker)
                            .padding(.horizontal, 32)
                            .padding(.top, 8)
                    }
                    
                    // 3. Student Pills Block
                    studentPillsSection
                        .padding(.horizontal, 32)
                        .padding(.top, 20)
                    
                    Divider()
                        .padding(.horizontal, 32)
                        .padding(.vertical, 20)
                    
                    // 4. Inbox/Scheduling Status Row
                    inboxStatusSection
                        .padding(.horizontal, 32)
                    
                    Divider()
                        .padding(.horizontal, 32)
                        .padding(.vertical, 20)
                    
                    // 7. Notes Section
                    notesSection
                        .padding(.horizontal, 32)
                        .padding(.top, 24)
                        .padding(.bottom, 32)
                    
                    // Progress buttons row below Notes
                    HStack(spacing: 12) {
                        Button { selectJustPresented() } label: {
                            StatePill(
                                title: "Just Presented",
                                systemImage: "checkmark.circle.fill",
                                tint: .green,
                                active: isJustPresentedActive
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)

                        Button { selectPreviouslyPresented() } label: {
                            StatePill(
                                title: "Previously Presented",
                                systemImage: "clock.badge.checkmark",
                                tint: .green,
                                active: isPreviouslyPresentedActive
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)

                        Button { selectNeedsAnother() } label: {
                            StatePill(
                                title: "Needs Another Presentation",
                                systemImage: "arrow.clockwise.circle.fill",
                                tint: .orange,
                                active: isNeedsAnotherActive
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 16)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 640)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                    Spacer()

                    Button("Cancel") {
                        if let onDone {
                            onDone()
                        } else {
                            dismiss()
                        }
                    }

                    Button("Save") {
                        save()
                    }
                    .bold()
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
            }
        }
        .alert("Delete Lesson?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                delete()
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingAddStudentSheet) {
            AddStudentView()
        }
        .overlay(alignment: .top) {
            if showMovedBanner {
                MovedStudentsBanner(studentNames: movedStudentNames)
            }
        }
        .sheet(isPresented: $showingMoveStudentsSheet) {
            MoveStudentsSheet(
                lessonName: lessonName,
                students: selectedStudentsList,
                studentsToMove: $studentsToMove,
                selectedStudentIDs: selectedStudentIDs,
                onMove: {
                    moveStudentsToInbox()
                    showingMoveStudentsSheet = false
                },
                onCancel: {
                    studentsToMove = []
                    showingMoveStudentsSheet = false
                }
            )
            #if os(macOS)
            .frame(minWidth: 420, minHeight: 520)
            .presentationSizing(.fitted)
            #endif
        }
        .onAppear {
            lessonPickerVM.configure(lessons: lessons, students: studentsAll)
            lessonPickerVM.selectLesson(studentLesson.lessonID)
            if autoFocusLessonPicker { lessonPickerFocused = true }
        }
        .onChange(of: lessons.map { $0.id }) { _, _ in
            lessonPickerVM.configure(lessons: lessons, students: studentsAll)
        }
        .onChange(of: lessonPickerVM.selectedLessonID) { _, newValue in
            if let newID = newValue {
                // Just update local state, don't save to model
                editingLessonID = newID
                
                // Hide the lesson picker after selection
                showLessonPicker = false
            }
        }
        .onChange(of: showingStudentPickerPopover) { _, isShowing in
            // Don't let student picker affect lesson picker state
            if !isShowing && lessonPickerFocused {
                lessonPickerFocused = false
            }
        }
        .onChange(of: needsAnotherPresentation) { _, newValue in
            // If toggled on and user doesn't schedule, create an unscheduled re-present entry if it doesn't exist
            if newValue {
                let sameStudents = Set(selectedStudentIDs)
                let exists = studentLessonsAll.contains { sl in
                    sl.resolvedLessonID == editingLessonID && sl.scheduledFor == nil && !sl.isGiven && Set(sl.resolvedStudentIDs) == sameStudents
                }
                if !exists {
                    let newStudentLesson = StudentLesson(
                        id: UUID(),
                        lessonID: editingLessonID,
                        studentIDs: Array(sameStudents),
                        createdAt: Date(),
                        scheduledFor: nil,
                        givenAt: nil,
                        notes: "",
                        needsPractice: false,
                        needsAnotherPresentation: false,
                        followUpWork: ""
                    )
                    newStudentLesson.students = studentsAll.filter { sameStudents.contains($0.id) }
                    newStudentLesson.lesson = lessons.first(where: { $0.id == editingLessonID })
                    modelContext.insert(newStudentLesson)
                    try? modelContext.save()
                }
            }
        }
    }

    private var lessonPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            LessonPickerSection(
                viewModel: lessonPickerVM,
                resolvedLesson: resolvedPickerLesson,
                isFocused: $lessonPickerFocused
            )
        }
    }
    
    private func studentChip(for student: Student) -> some View {
        HStack(spacing: 6) {
            Text(displayName(for: student))
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
            Button {
                selectedStudentIDs.remove(student.id)
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
    
    private var scheduleStatusText: String {
        guard let date = scheduledFor else { return "Not Scheduled Yet" }
        let datePart = StudentLessonDetailUtilities.Formatters.scheduleDay.string(from: date)
        let hour = calendar.component(.hour, from: date)
        let period = hour < 12 ? "Morning" : "Afternoon"
        return "\(datePart) in the \(period)"
    }

    private func displayName(for student: Student) -> String {
        return StudentFormatter.displayName(for: student)
    }

    private func applyEditsToModel() {
        let vm = StudentLessonDetailActions()
        vm.applyEditsToModel(
            studentLesson: studentLesson,
            editingLessonID: editingLessonID,
            scheduledFor: scheduledFor,
            givenAt: givenAt,
            isPresented: isPresented,
            notes: notes,
            needsAnotherPresentation: needsAnotherPresentation,
            selectedStudentIDs: selectedStudentIDs,
            studentsAll: studentsAll,
            lessons: lessons,
            calendar: calendar
        )
    }

    private func saveImmediate() {
        applyEditsToModel()
        try? modelContext.save()
    }

    private func save() {
        // Capture prior presented state
        let wasGiven = studentLesson.isPresented || studentLesson.givenAt != nil

        // Apply local edits to the model
        applyEditsToModel()

        // Auto-create next lesson in group when marking presented
        let nowGiven = isPresented || (givenAt != nil)

        // Dual-write to Engagement Lifecycle (Option A)
        if useEngagementLifecycle, nowGiven {
            do {
                let _ = try LifecycleService.recordPresentationAndExplodeWork(
                    from: studentLesson,
                    presentedAt: AppCalendar.startOfDay(givenAt ?? Date()),
                    modelContext: modelContext
                )
            } catch {
            }
        }

        let vm = StudentLessonDetailActions()
        vm.autoCreateNextIfNeeded(
            wasGiven: wasGiven,
            nowGiven: nowGiven,
            nextLesson: nil,
            selectedStudentIDs: selectedStudentIDs,
            studentsAll: studentsAll,
            lessons: lessons,
            studentLessonsAll: studentLessonsAll,
            context: modelContext
        )

        do {
            try modelContext.save()
            // Notify agenda/inbox to refresh immediately after save
            StudentLessonDetailUtilities.notifyInboxRefresh()

            if let onDone {
                onDone()
            } else {
                dismiss()
            }
        } catch {
            // Handle save error if needed
        }
    }

    private func delete() {
        // Capture the id and context to perform deletion after dismiss
        let id = studentLesson.id
        let ctx = modelContext

        // Dismiss UI first so no view tries to read this instance during the same render pass
        if let onDone {
            onDone()
        } else {
            dismiss()
        }

        // Delete on the next runloop tick by refetching a fresh instance
        DispatchQueue.main.async {
            let desc = FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.id == id })
            if let toDelete = try? ctx.fetch(desc).first {
                // Force-load commonly faulted attributes before deleting to avoid SwiftData traps
                _ = toDelete.studentIDs
                ctx.delete(toDelete)
                try? ctx.save()
            }
            // Notify agenda/inbox to refresh after deletion
            StudentLessonDetailUtilities.notifyInboxRefresh()
        }
    }

    private func moveStudentsToInbox() {
        guard !studentsToMove.isEmpty, let currentLesson = lessonObject else { return }
        let vm = StudentLessonDetailActions()
        movedStudentNames = vm.moveStudentsToInbox(
            currentLesson: currentLesson,
            studentsToMove: studentsToMove,
            studentsAll: studentsAll,
            studentLessonsAll: studentLessonsAll,
            context: modelContext
        )
        selectedStudentIDs.subtract(studentsToMove)
        studentsToMove.removeAll()
        showMovedBanner = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { showMovedBanner = false }
    }

    // MARK: - Progress Buttons Helpers
    private var isJustPresentedActive: Bool {
        if !isPresented { return false }
        guard let date = givenAt else { return false }
        return calendar.isDateInToday(date)
    }
    private var isPreviouslyPresentedActive: Bool {
        isPresented && !isJustPresentedActive
    }
    private var isNeedsAnotherActive: Bool {
        needsAnotherPresentation && !isPresented
    }
    private func selectJustPresented() {
        isPresented = true
        givenAt = calendar.startOfDay(for: Date())
        needsAnotherPresentation = false
    }
    private func selectPreviouslyPresented() {
        isPresented = true
        // Leave givenAt unchanged (user can set elsewhere); ensure exclusivity
        needsAnotherPresentation = false
        if let date = givenAt, calendar.isDateInToday(date) {
            givenAt = nil
        }
    }
    private func selectNeedsAnother() {
        isPresented = false
        givenAt = nil
        needsAnotherPresentation = true
    }

    // Equal-width pill used by progress buttons
    private struct StatePill: View {
        let title: String
        let systemImage: String
        let tint: Color
        var active: Bool = false
        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .foregroundStyle(tint)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(active ? 0.20 : 0.10))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1)
            )
        }
    }
}

