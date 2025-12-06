import SwiftUI
import SwiftData

#if os(macOS)
import AppKit
#endif

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
    @State private var needsPractice: Bool
    @State private var needsAnotherPresentation: Bool
    @State private var followUpWork: String

    @StateObject private var lessonPickerVM: LessonPickerViewModel
    @State private var lessonPickerFocused: Bool = false

    @State private var selectedStudentIDs: Set<UUID> = []
    @State private var showingAddStudentSheet = false
    @State private var showingStudentPickerPopover = false
    @State private var studentSearchText: String = ""
    @State private var showDeleteAlert: Bool = false

    private enum LevelFilter: String, CaseIterable {
        case all = "All"
        case lower = "Lower"
        case upper = "Upper"
    }

    @State private var studentLevelFilter: LevelFilter = .all
    @State private var didPlanNext: Bool = false
    @State private var showPlannedBanner: Bool = false
    @State private var showingMoveStudentsSheet = false
    @State private var studentsToMove: Set<UUID> = []
    @State private var showMovedBanner: Bool = false
    @State private var movedStudentNames: [String] = []
    @State private var isOptionDown: Bool = false

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
        _needsPractice = State(initialValue: studentLesson.needsPractice)
        _needsAnotherPresentation = State(initialValue: studentLesson.needsAnotherPresentation)
        _followUpWork = State(initialValue: studentLesson.followUpWork)
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
            sl.lessonID == next.id && Set(sl.studentIDs) == sameStudents && sl.givenAt == nil
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
            newStudentLesson.syncSnapshotsFromRelationships()
            modelContext.insert(newStudentLesson)
            try? modelContext.save()
        }
        didPlanNext = true

        showPlannedBanner = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showPlannedBanner = false
        }
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
            sl.lessonID == currentLesson.id && sl.scheduledFor == nil && !sl.isGiven && Set(sl.studentIDs) == targetSet
        })

        if let ex = existing {
            // Ensure relationships are up to date
            ex.students = studentsAll.filter { targetSet.contains($0.id) }
            ex.lesson = currentLesson
            ex.syncSnapshotsFromRelationships()
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
            newStudentLesson.syncSnapshotsFromRelationships()
            modelContext.insert(newStudentLesson)
        }

        // Remove the students from the current lesson selection
        selectedStudentIDs.subtract(studentsToMove)
        studentsToMove.removeAll()

        // Save changes
        try? modelContext.save()

        // Notify agenda/inbox to refresh immediately
        NotificationCenter.default.post(name: Notification.Name("PlanningInboxNeedsRefresh"), object: nil)

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
    
    private var absentIDsForSelection: Set<UUID> {
        let ids = Set(selectedStudentsList.compactMap { s -> UUID? in
            let id = s.id
            let status = modelContext.attendanceStatuses(for: [id], on: scheduledFor ?? Date())[id]
            return status == .absent ? id : nil
        })
        return ids
    }
    
    private var filteredStudentsForPicker: [Student] {
        let query = studentSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let searched: [Student]
        if query.isEmpty {
            searched = studentsAll
        } else {
            searched = studentsAll.filter { s in
                let f = s.firstName.lowercased()
                let l = s.lastName.lowercased()
                let full = s.fullName.lowercased()
                return f.contains(query) || l.contains(query) || full.contains(query)
            }
        }
        let leveled: [Student] = searched.filter { s in
            switch studentLevelFilter {
            case .all: return true
            case .lower: return s.level == .lower
            case .upper: return s.level == .upper
            }
        }
        return leveled.sorted {
            let lhs = ($0.firstName, $0.lastName)
            let rhs = ($1.firstName, $1.lastName)
            if lhs.0.caseInsensitiveCompare(rhs.0) == .orderedSame {
                return lhs.1.caseInsensitiveCompare(rhs.1) == .orderedAscending
            }
            return lhs.0.caseInsensitiveCompare(rhs.0) == .orderedAscending
        }
    }

    private func displayName(for student: Student) -> String {
        return StudentFormatter.displayName(for: student)
    }

    private func dateChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.12))
            )
    }

    private var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE, MMM d, h:mm a")
        return formatter
    }()
    
    private var scheduleStatusText: String {
        guard let date = scheduledFor else {
            return "Not Scheduled Yet"
        }
        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate("EEEE, MMM d")
        let datePart = fmt.string(from: date)
        let hour = Calendar.current.component(.hour, from: date)
        let period = hour < 12 ? "Morning" : "Afternoon"
        return "\(datePart) in the \(period)"
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
                    
                    // 6. Notes Section
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
        VStack(spacing: 12) {
            Text(lessonName)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            
            // Subject / Category / Subcategory Pills
            if let lesson = lessonObject {
                HStack(spacing: 8) {
                    if !lesson.subject.isEmpty {
                        pillTag(lesson.subject, color: subjectColor)
                    }
                    if !lesson.group.isEmpty {
                        pillTag(lesson.group, color: .secondary.opacity(0.6))
                    }
                    // Subcategory could be added here if Lesson model has that property
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    /// Pill-style tag for subjects/categories
    private func pillTag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundColor(color)
            .background(
                Capsule()
                    .fill(color.opacity(0.15))
            )
    }
    
    /// 3. Student Pills + Add/Remove
    private var studentPillsSection: some View {
        VStack(spacing: 12) {
            // Student pills in a flowing wrap
            FlowLayout(spacing: 8) {
                ForEach(selectedStudentsList, id: \.id) { student in
                    studentChip(for: student)
                }
            }
            
            // Buttons below
            HStack(spacing: 12) {
                Button {
                    showingStudentPickerPopover = true
                } label: {
                    Label("Add/Remove Students", systemImage: "person.2.badge.gearshape")
                        .font(.system(size: AppTheme.FontSize.callout, design: .rounded))
                }
                .buttonStyle(.bordered)
                .popover(isPresented: $showingStudentPickerPopover, arrowEdge: .top) {
                    StudentPickerPopover(
                        students: studentsAll,
                        selectedIDs: $selectedStudentIDs,
                        onDone: { showingStudentPickerPopover = false }
                    )
                    .padding(12)
                    .frame(minWidth: 320)
                }
                
                if selectedStudentsList.count > 1 && !isPresented {
                    Button {
                        studentsToMove = []
                        showingMoveStudentsSheet = true
                    } label: {
                        Label("Move Students", systemImage: "arrow.right.square")
                            .font(.system(size: AppTheme.FontSize.callout, design: .rounded))
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    /// 4. Inbox/Scheduling Status
    private var inboxStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "tray")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 16))
                Text("Inbox Status")
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            
            // Show schedule status or allow scheduling
            if scheduledFor != nil {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .foregroundStyle(.blue)
                        .font(.system(size: 14))
                    Text("Scheduled: \(scheduleStatusText)")
                        .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                        .foregroundColor(.blue)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.blue.opacity(0.1))
                )
                
                Button {
                    scheduledFor = nil
                } label: {
                    Label("Remove from Schedule", systemImage: "xmark.circle")
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))
                    Text("Unscheduled")
                        .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )
                
                OptionalDatePicker(
                    toggleLabel: "Schedule Lesson",
                    dateLabel: "Schedule For",
                    date: $scheduledFor,
                    displayedComponents: [.date, .hourAndMinute],
                    defaultHour: 9
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    /// 5. Lesson Progress Section (consolidated presentation, practice, re-present, follow-up)
    private var lessonProgressSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 16))
                Text("Lesson Progress")
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                // Presented Toggle + Date
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Toggle(isOn: $isPresented) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(isPresented ? .green : .secondary)
                                    .font(.system(size: 18))
                                Text("Presented")
                                    .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
                            }
                        }
                        .toggleStyle(.button)
                        .buttonStyle(.borderless)
                        .tint(.green)
                        
                        Spacer()
                        
                        // Quick date picker button
                        if isPresented {
                            Button {
                                presentedDate = calendar.startOfDay(for: givenAt ?? Date())
                                showPresentedPopover.toggle()
                            } label: {
                                HStack(spacing: 4) {
                                    if let date = givenAt {
                                        Text(date, style: .date)
                                            .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                                    } else {
                                        Text("Add Date")
                                            .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                                    }
                                    Image(systemName: "calendar")
                                        .font(.system(size: 12))
                                }
                                .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: $showPresentedPopover, arrowEdge: .top) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Presentation Date")
                                        .font(.headline)
                                    DatePicker("Date", selection: $presentedDate, displayedComponents: [.date])
                                    #if os(macOS)
                                    .datePickerStyle(.field)
                                    #else
                                    .datePickerStyle(.compact)
                                    #endif
                                    HStack {
                                        Button("Clear") {
                                            givenAt = nil
                                            showPresentedPopover = false
                                        }
                                        Spacer()
                                        Button("Set") {
                                            givenAt = calendar.startOfDay(for: presentedDate)
                                            showPresentedPopover = false
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
                                }
                                .padding(12)
                                .frame(minWidth: 280)
                            }
                        }
                    }
                }
                
                // Needs Practice Flag
                HStack {
                    Toggle(isOn: $needsPractice) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(needsPractice ? .purple : .secondary)
                                .font(.system(size: 18))
                            Text("Needs Practice")
                                .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
                        }
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.borderless)
                    .tint(.purple)
                    
                    Spacer()
                }
                
                // Needs Another Presentation Flag
                HStack {
                    Toggle(isOn: $needsAnotherPresentation) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .foregroundStyle(needsAnotherPresentation ? .orange : .secondary)
                                .font(.system(size: 18))
                            Text("Needs Another Presentation")
                                .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
                        }
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.borderless)
                    .tint(.orange)
                    
                    Spacer()
                    
                    // Re-present button appears when flagged
                    if needsAnotherPresentation {
                        Button {
                            rePresentDate = defaultRePresentDate()
                            showRePresentPopover.toggle()
                        } label: {
                            Label("Schedule", systemImage: "calendar.badge.clock")
                                .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                        }
                        .buttonStyle(.bordered)
                        .popover(isPresented: $showRePresentPopover, arrowEdge: .top) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Schedule Re-presentation")
                                    .font(.headline)
                                DatePicker("Date", selection: $rePresentDate, displayedComponents: [.date])
                                #if os(macOS)
                                .datePickerStyle(.field)
                                #else
                                .datePickerStyle(.compact)
                                #endif
                                HStack {
                                    Spacer()
                                    Button("Schedule") {
                                        scheduleRePresent(on: rePresentDate)
                                        showRePresentPopover = false
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                            .padding(12)
                            .frame(minWidth: 280)
                        }
                    }
                }
                
                // Follow-Up Work
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.yellow)
                            .font(.system(size: 16))
                        Text("Follow-Up Work")
                            .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
                    }
                    
                    TextField("Describe follow-up work…", text: $followUpWork, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                }
                
                // Next lesson section (when presented)
                if isPresented, let next = nextLessonInGroup {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.right.circle")
                                .foregroundStyle(.blue)
                                .font(.system(size: 16))
                            Text("Next in Group: \(next.name)")
                                .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
                        }
                        
                        Button {
                            planNextLessonInGroup()
                        } label: {
                            Label("Plan Next Lesson", systemImage: "calendar.badge.plus")
                                .font(.system(size: AppTheme.FontSize.callout, design: .rounded))
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(didPlanNext || studentLessonsAll.contains { sl in
                            sl.lessonID == next.id && Set(sl.studentIDs) == Set(selectedStudentIDs) && sl.givenAt == nil
                        })
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            )
        }
    }
    
    /// 6. Notes Section with subtle ruled-paper aesthetic
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "note.text")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 16))
                Text("Notes")
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            
            ZStack(alignment: .topLeading) {
                // Subtle ruled-paper background
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { _ in
                        Divider()
                            .background(Color.secondary.opacity(0.1))
                            .padding(.vertical, 16)
                    }
                }
                .allowsHitTesting(false)
                
                TextEditor(text: $notes)
                    .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(minHeight: 180)
                    .padding(8)
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.textBackgroundColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Helper Views (kept for compatibility)
    
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

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text("Scheduled For")
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            OptionalDatePicker(
                toggleLabel: "Schedule",
                dateLabel: "Schedule For",
                date: $scheduledFor,
                displayedComponents: [.date, .hourAndMinute],
                defaultHour: 9
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var givenSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "clock.badge.checkmark")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text("Presented")
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Toggle("Presented", isOn: $isPresented)

            Toggle("Add date", isOn: Binding(
                get: { givenAt != nil },
                set: { newValue in
                    givenAt = newValue ? (givenAt ?? Date()) : nil
                }
            ))

            if givenAt != nil {
                DatePicker("Date", selection: Binding(
                    get: { givenAt ?? Date() },
                    set: { givenAt = calendar.startOfDay(for: $0) }
                ), displayedComponents: [.date])
                #if os(macOS)
                .datePickerStyle(.field)
                #else
                .datePickerStyle(.compact)
                #endif
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nextLessonSection: some View {
        Group {
            if isPresented {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.plus")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text("Next Lesson in Group")
                            .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    if let next = nextLessonInGroup {
                        Text(next.name)
                            .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                        Button {
                            planNextLessonInGroup()
                        } label: {
                            Label("Plan Next Lesson in Group", systemImage: "calendar.badge.plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(didPlanNext || studentLessonsAll.contains { sl in
                            sl.lessonID == next.id && Set(sl.studentIDs) == Set(selectedStudentIDs) && sl.givenAt == nil
                        })
                    } else {
                        Text("No next lesson available")
                            .font(.system(size: AppTheme.FontSize.body, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var flagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "flag")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text("Flags")
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Toggle("Needs Practice", isOn: $needsPractice)
            Toggle("Needs Another Presentation", isOn: $needsAnotherPresentation)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var followUpSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text("Follow Up Work")
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            TextField("Follow Up Work", text: $followUpWork)
                .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func markPresented(on date: Date) {
        let normalized = calendar.startOfDay(for: date)
        isPresented = true
        givenAt = normalized
        saveImmediate()
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        showBanner(text: "Marked Presented (\(fmt.string(from: normalized)))", color: .green)
    }

    private func addPracticeIfNeeded() {
        needsPractice = true
        // Avoid duplicate Practice work
        let hasPracticeWork = workModels.contains { work in
            work.studentLessonID == studentLesson.id && work.workType == .practice
        }
        if !hasPracticeWork {
            let practiceWork = WorkModel(
                id: UUID(),
                title: "Practice: \(lessonObject?.name ?? "Lesson")",
                studentIDs: Array(selectedStudentIDs),
                workType: .practice,
                studentLessonID: studentLesson.id,
                notes: "",
                createdAt: Date()
            )
            modelContext.insert(practiceWork)
        }
        saveImmediate()
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
        newStudentLesson.syncSnapshotsFromRelationships()
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

    private func saveImmediate() {
        // Persist minimal fields immediately without dismissing the sheet
        studentLesson.lessonID = editingLessonID
        studentLesson.scheduledFor = scheduledFor
        studentLesson.givenAt = givenAt.map { calendar.startOfDay(for: $0) }
        studentLesson.isPresented = isPresented
        studentLesson.notes = notes
        studentLesson.needsPractice = needsPractice
        studentLesson.needsAnotherPresentation = needsAnotherPresentation
        studentLesson.followUpWork = followUpWork
        studentLesson.studentIDs = Array(selectedStudentIDs)

        studentLesson.students = studentsAll.filter { selectedStudentIDs.contains($0.id) }
        studentLesson.lesson = lessons.first(where: { $0.id == editingLessonID })
        studentLesson.syncSnapshotsFromRelationships()

        try? modelContext.save()
    }

    private func save() {
        // Commit all local editing state to the model
        studentLesson.lessonID = editingLessonID
        studentLesson.scheduledFor = scheduledFor
        studentLesson.givenAt = givenAt.map { calendar.startOfDay(for: $0) }
        studentLesson.isPresented = isPresented
        studentLesson.notes = notes
        studentLesson.needsPractice = needsPractice
        studentLesson.needsAnotherPresentation = needsAnotherPresentation
        studentLesson.followUpWork = followUpWork
        studentLesson.studentIDs = Array(selectedStudentIDs)

        // Update relationships
        studentLesson.students = studentsAll.filter { selectedStudentIDs.contains($0.id) }
        studentLesson.lesson = lessons.first(where: { $0.id == editingLessonID })
        studentLesson.syncSnapshotsFromRelationships()
        
        // Auto-create a WorkModel for Needs Practice when flagged
        if needsPractice {
            let hasPracticeWork = workModels.contains { work in
                work.studentLessonID == studentLesson.id && work.workType == .practice
            }
            if !hasPracticeWork {
                let practiceWork = WorkModel(
                    id: UUID(),
                    title: "Practice: \(lessonObject?.name ?? "Lesson")",
                    studentIDs: Array(selectedStudentIDs),
                    workType: .practice,
                    studentLessonID: studentLesson.id,
                    notes: "",
                    createdAt: Date()
                )
                modelContext.insert(practiceWork)
            }
        }

        // Auto-create a WorkModel for Follow Up Work when provided
        let trimmedFollowUp = followUpWork.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFollowUp.isEmpty {
            let hasDuplicateFollowUp = workModels.contains { work in
                work.studentLessonID == studentLesson.id &&
                work.workType == .followUp &&
                work.notes.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(trimmedFollowUp) == .orderedSame
            }
            if !hasDuplicateFollowUp {
                let followUp = WorkModel(
                    id: UUID(),
                    title: "Follow Up: \(lessonObject?.name ?? "Lesson")",
                    studentIDs: Array(selectedStudentIDs),
                    workType: .followUp,
                    studentLessonID: studentLesson.id,
                    notes: trimmedFollowUp,
                    createdAt: Date()
                )
                modelContext.insert(followUp)
            }
        }

        do {
            try modelContext.save()

            // Notify agenda/inbox to refresh immediately after deletion
            NotificationCenter.default.post(name: Notification.Name("PlanningInboxNeedsRefresh"), object: nil)

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
        NotificationCenter.default.post(name: Notification.Name("PlanningInboxNeedsRefresh"), object: nil)

        // Now dismiss after the @Query has updated
        if let onDone {
            onDone()
        } else {
            dismiss()
        }
    }
}

#Preview {
    Text("StudentLessonDetailView preview requires real model data")
}

#if os(macOS)
struct OptionKeyMonitor: NSViewRepresentable {
    let onChange: (Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.start()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Coordinator {
        let onChange: (Bool) -> Void
        private var monitor: Any?

        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
        }

        func start() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.onChange(event.modifierFlags.contains(.option))
                return event
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
#endif

// MARK: - FlowLayout Helper

/// A simple flow layout that wraps content horizontally
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            let position = result.positions[index]
            subview.place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if currentX + size.width > maxWidth && currentX > 0 {
                    // Move to next line
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: currentX, y: currentY))
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}

