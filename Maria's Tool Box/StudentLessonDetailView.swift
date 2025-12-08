import SwiftUI
import SwiftData

struct StudentLessonDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
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

    @State private var didPlanNext: Bool = false
    @State private var showPlannedBanner: Bool = false
    @State private var showingMoveStudentsSheet = false
    @State private var studentsToMove: Set<UUID> = []
    @State private var showMovedBanner: Bool = false
    @State private var movedStudentNames: [String] = []

    @State private var showPresentedPopover: Bool = false
    @State private var presentedDate: Date = Date()
    @State private var showRePresentPopover: Bool = false
    @State private var rePresentDate: Date = Date()
    @State private var showQuickBanner: Bool = false
    @State private var quickBannerText: String = ""
    @State private var quickBannerColor: Color = .green
    @State private var showLessonPicker: Bool = false

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
        let currentSubject = current.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentGroup = current.group.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentSubject.isEmpty, !currentGroup.isEmpty else { return nil }
        let candidates = lessons.filter { l in
            l.subject.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(currentSubject) == .orderedSame &&
            l.group.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(currentGroup) == .orderedSame
        }
        .sorted { $0.orderInGroup < $1.orderInGroup }
        guard let idx = candidates.firstIndex(where: { $0.id == current.id }), idx + 1 < candidates.count else { return nil }
        return candidates[idx + 1]
    }

    private func planNextLessonInGroup() {
        guard let next = nextLessonInGroup else { return }
        let sameStudents = Set(selectedStudentIDs)
        let exists = studentLessonsAll.contains { sl in
            sl.resolvedLessonID == next.id && Set(sl.resolvedStudentIDs) == sameStudents && sl.givenAt == nil
        }
        if !exists {
            let newStudentLesson = StudentLesson(
                id: UUID(),
                lessonID: next.id,
                studentIDs: Array(selectedStudentIDs),
                createdAt: Date(),
                scheduledFor: nil,
                givenAt: nil,
                notes: "",
                needsPractice: false,
                needsAnotherPresentation: false,
                followUpWork: ""
            )
            newStudentLesson.students = studentsAll.filter { sameStudents.contains($0.id) }
            newStudentLesson.lesson = lessons.first(where: { $0.id == next.id })
            modelContext.insert(newStudentLesson)
            try? modelContext.save()
        }
        didPlanNext = true

        showPlannedBanner = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showPlannedBanner = false
        }
        notifyInboxRefresh()
    }
    
    private func moveStudentsToInbox() {
        guard !studentsToMove.isEmpty, let currentLesson = lessonObject else { return }

        // Get names for the banner
        movedStudentNames = studentsAll
            .filter { studentsToMove.contains($0.id) }
            .map { displayName(for: $0) }

        // Find or create one unscheduled group StudentLesson for these students
        let targetSet = studentsToMove
        let existing = studentLessonsAll.first(where: { sl in
            sl.resolvedLessonID == currentLesson.id && sl.scheduledFor == nil && !sl.isGiven && Set(sl.resolvedStudentIDs) == targetSet
        })

        if let ex = existing {
            // Ensure relationships are up to date
            ex.students = studentsAll.filter { targetSet.contains($0.id) }
            ex.lesson = currentLesson
        } else {
            let newStudentLesson = StudentLesson(
                id: UUID(),
                lessonID: currentLesson.id,
                studentIDs: Array(targetSet),
                createdAt: Date(),
                scheduledFor: nil,
                givenAt: nil,
                notes: "",
                needsPractice: false,
                needsAnotherPresentation: false,
                followUpWork: ""
            )
            newStudentLesson.students = studentsAll.filter { targetSet.contains($0.id) }
            newStudentLesson.lesson = currentLesson
            modelContext.insert(newStudentLesson)
        }

        // Remove the students from the current lesson selection
        selectedStudentIDs.subtract(studentsToMove)
        studentsToMove.removeAll()

        // Save changes
        try? modelContext.save()

        // Notify agenda/inbox to refresh immediately
        notifyInboxRefresh()

        // Show confirmation banner
        showMovedBanner = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            showMovedBanner = false
        }
    }

    private var selectedStudentsList: [Student] {
        studentsAll
            .filter { selectedStudentIDs.contains($0.id) }
            .sorted { $0.firstName.localizedCaseInsensitiveCompare($1.firstName) == .orderedAscending }
    }
    
    // Added as per instruction 1
    private var openLinkedWorks: [WorkModel] {
        workModels.filter { w in
            w.studentLessonID == studentLesson.id &&
            (w.workType == .practice || w.workType == .followUp) &&
            w.isOpen
        }
    }

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
                        // Minimal "Change Lesson" button
                        HStack {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showLessonPicker = true
                                }
                            } label: {
                                Label("Change Lesson…", systemImage: "pencil")
                                    .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            Spacer()
                        }
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
                    
                    // 5. Lesson Progress Section
                    lessonProgressSection
                        .padding(.horizontal, 32)

                    // 6. Linked Work Section
                    linkedWorkSection
                        .padding(.horizontal, 32)
                        .padding(.top, 24)

                    // 7. Notes Section
                    notesSection
                        .padding(.horizontal, 32)
                        .padding(.top, 24)
                        .padding(.bottom, 32)
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
            Group {
                if showPlannedBanner {
                    PlannedLessonBanner()
                } else if showMovedBanner {
                    MovedStudentsBanner(studentNames: movedStudentNames)
                } else if showQuickBanner {
                    quickBanner
                }
            }
            .allowsHitTesting(false)
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
        .sheet(isPresented: $showFollowUpSheet) {
            VStack(alignment: .leading, spacing: 12) {
                Text("New Follow-Up")
                    .font(.headline)
                TextField("Describe follow-up work…", text: $followUpDraft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                HStack {
                    Spacer()
                    Button("Cancel") { showFollowUpSheet = false }
                    Button("Add") {
                        let trimmed = followUpDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            // Create follow-up work linked to this student lesson
                            let work = WorkModel(
                                id: UUID(),
                                title: "Follow Up: \(lessonObject?.name ?? "Lesson")",
                                workType: .followUp,
                                studentLessonID: studentLesson.id,
                                notes: trimmed,
                                createdAt: Date()
                            )
                            work.participants = Array(selectedStudentIDs).map { sid in WorkParticipantEntity(studentID: sid, completedAt: nil, work: work) }
                            modelContext.insert(work)
                            try? modelContext.save()
                        }
                        showFollowUpSheet = false
                        showBanner(text: "Follow-up added", color: .yellow)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
            #if os(macOS)
            .frame(minWidth: 420)
            .presentationSizing(.fitted)
            #endif
        }
        .onAppear {
            presentedDate = calendar.startOfDay(for: givenAt ?? Date())
            rePresentDate = defaultRePresentDate()
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
                    notifyInboxRefresh()
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
    
    // MARK: - New Redesigned Sections
    
    /// 1. Lesson Header: Large title + subject/category pills
    private var lessonHeaderSection: some View {
        StudentLessonHeaderView(
            lessonName: lessonName,
            subject: lessonObject?.subject ?? "",
            group: lessonObject?.group ?? "",
            subjectColor: subjectColor
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
    
    /// 5. Lesson Progress Section (replaced with extracted view)
    private var lessonProgressSection: some View {
        LessonProgressSection(
            subjectColor: subjectColor,
            isPresented: $isPresented,
            givenAt: $givenAt,
            needsAnotherPresentation: $needsAnotherPresentation,
            selectedStudentIDs: $selectedStudentIDs,
            lesson: lessonObject,
            nextLessonInGroup: nextLessonInGroup,
            studentLessonID: studentLesson.id,
            studentsAll: studentsAll,
            lessonsAll: lessons,
            studentLessonsAll: studentLessonsAll,
            didPlanNext: $didPlanNext,
            showPlannedBanner: $showPlannedBanner,
            showFollowUpSheet: $showFollowUpSheet,
            followUpDraft: $followUpDraft,
            showQuickBanner: $showQuickBanner,
            quickBannerText: $quickBannerText,
            quickBannerColor: $quickBannerColor
        )
    }
    
    /// 6. Linked Work Section (replaced with extracted view)
    private var linkedWorkSection: some View {
        LinkedWorkSection(
            works: openLinkedWorks,
            studentsAll: studentsAll,
            displayName: displayName(for:),
            iconAndColor: workIconAndColor(_:),
            onToggle: { work, studentID in toggleWorkCompletion(work, studentID: studentID) }
        )
    }

    /// 7. Notes Section with subtle ruled-paper aesthetic (replaced with extracted view)
    private var notesSection: some View { NotesSectionView(notes: $notes) }
    
    // MARK: - Helper Views (kept for compatibility)
    
    // Added as per instruction 2
    private func workIconAndColor(_ type: WorkModel.WorkType) -> (String, Color) {
        switch type {
        case .research: return ("magnifyingglass", .teal)
        case .followUp: return ("bolt.fill", .orange)
        case .practice: return ("arrow.triangle.2.circlepath", .purple)
        }
    }

    private func toggleWorkCompletion(_ work: WorkModel, studentID: UUID) {
        if work.isStudentCompleted(studentID) {
            work.markStudent(studentID, completedAt: nil)
        } else {
            work.markStudent(studentID, completedAt: Date())
        }
        try? modelContext.save()
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
    
    private var quickBanner: some View {
        Text(quickBannerText)
            .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(quickBannerColor.opacity(0.95))
            )
            .foregroundColor(.white)
            .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
            .padding(.top, 8)
    }

    private enum Formatters {
        static let scheduleDay: DateFormatter = {
            let f = DateFormatter()
            f.setLocalizedDateFormatFromTemplate("EEEE, MMM d")
            return f
        }()
    }

    private var scheduleStatusText: String {
        guard let date = scheduledFor else { return "Not Scheduled Yet" }
        let datePart = Formatters.scheduleDay.string(from: date)
        let hour = Calendar.current.component(.hour, from: date)
        let period = hour < 12 ? "Morning" : "Afternoon"
        return "\(datePart) in the \(period)"
    }

    private func displayName(for student: Student) -> String {
        return StudentFormatter.displayName(for: student)
    }

    private func notifyInboxRefresh() {
        NotificationCenter.default.post(name: Notification.Name("PlanningInboxNeedsRefresh"), object: nil)
    }

    private func applyEditsToModel() {
        studentLesson.lessonID = editingLessonID
        studentLesson.scheduledFor = scheduledFor
        studentLesson.givenAt = givenAt.map { calendar.startOfDay(for: $0) }
        studentLesson.isPresented = isPresented
        studentLesson.notes = notes
        studentLesson.needsAnotherPresentation = needsAnotherPresentation
        studentLesson.studentIDs = Array(selectedStudentIDs)
        studentLesson.students = studentsAll.filter { selectedStudentIDs.contains($0.id) }
        studentLesson.lesson = lessons.first(where: { $0.id == editingLessonID })
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
        if !wasGiven && nowGiven, let next = nextLessonInGroup {
            let sameStudents = Set(selectedStudentIDs)
            let exists = studentLessonsAll.contains { sl in
                sl.resolvedLessonID == next.id && Set(sl.resolvedStudentIDs) == sameStudents && sl.givenAt == nil
            }
            if !exists {
                let newStudentLesson = StudentLesson(
                    id: UUID(),
                    lessonID: next.id,
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
                newStudentLesson.lesson = lessons.first(where: { $0.id == next.id })
                modelContext.insert(newStudentLesson)
                // Notify inbox to refresh
                notifyInboxRefresh()
            }
        }

        do {
            try modelContext.save()
            // Notify agenda/inbox to refresh immediately after save
            notifyInboxRefresh()

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
        // Delete synchronously first to avoid views reading a detached object
        modelContext.delete(studentLesson)
        do {
            try modelContext.save()
        } catch {
            // Handle delete error if needed
        }

        // Notify agenda/inbox to refresh immediately after deletion
        notifyInboxRefresh()

        // Now dismiss after the @Query has updated
        if let onDone {
            onDone()
        } else {
            dismiss()
        }
    }

    private func addPracticeIfNeeded() {
        let hasPracticeWork = workModels.contains { work in
            work.studentLessonID == studentLesson.id && work.workType == .practice
        }
        if !hasPracticeWork {
            let practiceWork = WorkModel(
                id: UUID(),
                title: "Practice: \(lessonObject?.name ?? "Lesson")",
                workType: .practice,
                studentLessonID: studentLesson.id,
                notes: "",
                createdAt: Date()
            )
            practiceWork.participants = Array(selectedStudentIDs).map { sid in WorkParticipantEntity(studentID: sid, completedAt: nil, work: practiceWork) }
            modelContext.insert(practiceWork)
            try? modelContext.save()
        }
        showBanner(text: "Practice added", color: .purple)
    }

    private func scheduleRePresent(on date: Date) {
        // Schedule at 9 AM of the chosen date for consistency
        let startOfDay = calendar.startOfDay(for: date)
        let scheduled = calendar.date(byAdding: .hour, value: 9, to: startOfDay) ?? startOfDay

        let newStudentLesson = StudentLesson(
            id: UUID(),
            lessonID: editingLessonID,
            studentIDs: Array(selectedStudentIDs),
            createdAt: Date(),
            scheduledFor: scheduled,
            givenAt: nil,
            notes: "",
            needsPractice: false,
            needsAnotherPresentation: false,
            followUpWork: ""
        )
        newStudentLesson.students = selectedStudentsList
        newStudentLesson.lesson = lessonObject
        modelContext.insert(newStudentLesson)

        do { try modelContext.save() } catch {}

        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        showBanner(text: "Re-present scheduled for \(fmt.string(from: scheduled))", color: .blue)
    }

    private func defaultRePresentDate() -> Date {
        // Default to tomorrow (or next calendar day) at 9 AM
        let base = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.startOfDay(for: base)
    }

    // MARK: - Banner Views
    
    private func showBanner(text: String, color: Color = .green, autoHideAfter seconds: Double = 2.0) {
        quickBannerText = text
        quickBannerColor = color
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            showQuickBanner = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            withAnimation(.easeInOut(duration: 0.2)) { showQuickBanner = false }
        }
    }
}

