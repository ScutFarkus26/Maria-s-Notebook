import SwiftUI
import SwiftData
import OSLog

/// Reusable panel component for presentation workflow (can be used in sheets or embedded)
/// Contains the split-panel UI for presentation notes and work item creation
struct UnifiedPresentationWorkflowPanel: View {
    private static let logger = Logger.presentations
    // MARK: - Types
    
    struct WorkItemDraft: Identifiable {
        let id: UUID
        let studentID: UUID
        var title: String
        var kind: WorkKind
        var status: WorkStatus
        var completionOutcome: CompletionOutcome?
        var completionNote: String
        var checkInDate: Date?
        var dueDate: Date?
        var notes: String
        var showMoreDetails: Bool
        var checkInStyle: CheckInStyle
        
        init(studentID: UUID, title: String = "", kind: WorkKind = .practiceLesson, status: WorkStatus = .active, checkInStyle: CheckInStyle = .flexible) {
            self.id = UUID()
            self.studentID = studentID
            self.title = title
            self.kind = kind
            self.status = status
            self.completionOutcome = nil
            self.completionNote = ""
            self.checkInDate = nil
            self.dueDate = nil
            self.notes = ""
            self.showMoreDetails = false
            self.checkInStyle = checkInStyle
        }
    }
    
    // MARK: - Input
    
    @Bindable var presentationViewModel: PostPresentationFormViewModel
    let students: [Student]
    let lessonName: String
    let lessonID: UUID
    let onComplete: () -> Void
    let onCancel: () -> Void
    
    // Optional binding to trigger completion from external toolbar (for sheet context)
    var triggerCompletion: Binding<Bool>?
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var modelContext
    @Environment(SaveCoordinator.self) private var saveCoordinator
    
    @Query(sort: \Lesson.sortIndex) private var lessons: [Lesson]
    @Query private var lessonAssignments: [LessonAssignment]
    @Query(sort: \WorkModel.createdAt, order: .reverse) private var allWorkModels: [WorkModel]
    
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    
    // MARK: - State
    
    // Work drafts: studentID -> [WorkItemDraft]
    @State private var workDrafts: [UUID: [WorkItemDraft]] = [:]
    
    @State private var isSaving: Bool = false
    @State private var activePanel: PanelFocus = .presentation
    @State private var showBulkAppliedToast: Bool = false
    @State private var bulkAppliedMessage: String = ""
    @State private var showStudentNavigator: Bool = false
    @State private var bulkCheckInStyle: CheckInStyle = .flexible
    @Namespace private var studentScrollAnchor
    
    private enum PanelFocus: Sendable {
        case presentation
        case work
    }
    
    // MARK: - Computed
    
    private var sortedStudents: [Student] {
        students.sorted(by: StudentSortComparator.byFirstName)
    }
    
    /// Existing work items for this lesson and these students
    private func existingWorkItems(for studentID: UUID) -> [WorkModel] {
        let studentIDString = studentID.uuidString
        let lessonIDString = lessonID.uuidString
        return allWorkModels.filter { work in
            work.studentID == studentIDString && work.lessonID == lessonIDString
        }
    }
    
    var canComplete: Bool {
        // Must have valid presentation status
        guard presentationViewModel.canDismiss else { return false }
        
        // At least one work item must be created
        return workDrafts.values.contains { !$0.isEmpty }
    }
    
    // Progress tracking
    private var studentsWithNotes: Int {
        presentationViewModel.entries.values.filter { !$0.observation.isEmpty }.count
    }
    
    private var studentsWithUnderstanding: Int {
        presentationViewModel.entries.values.filter { $0.understandingLevel != 3 }.count
    }
    
    private var hasGroupObservation: Bool {
        !presentationViewModel.groupObservation.isEmpty
    }
    
    // MARK: - Body
    
    var body: some View {
        Group {
            #if os(iOS)
            if horizontalSizeClass == .compact {
                compactLayout
            } else {
                splitPanelLayout
            }
            #else
            splitPanelLayout
            #endif
        }
        .onChange(of: triggerCompletion?.wrappedValue) { _, newValue in
            if let newValue, newValue {
                completeWorkflow()
                triggerCompletion?.wrappedValue = false
            }
        }
        .overlay(alignment: .top) {
            if showBulkAppliedToast {
                toastView
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
    
    // MARK: - Toast View
    
    private var toastView: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(bulkAppliedMessage)
                .font(.workflowCallout)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        )
    }
    

    
    // MARK: - Split Panel Layout (iPad/macOS)
    
    private var splitPanelLayout: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Left Panel: Presentation
                presentationPanel
                    .frame(width: geometry.size.width * 0.45)
                    .background(Color.primary.opacity(0.02))
                
                Divider()
                
                // Right Panel: Work Creation
                workCreationPanel
                    .frame(width: geometry.size.width * 0.55)
            }
        }
        .frame(minWidth: 1000, minHeight: 700)
    }
    
    // MARK: - Compact Layout (iPhone)
    
    private var compactLayout: some View {
        TabView(selection: $activePanel) {
            presentationPanel
                .tag(PanelFocus.presentation)
                .tabItem {
                    Label("Presentation", systemImage: SFSymbol.Education.bookFill)
                }
            
            workCreationPanel
                .tag(PanelFocus.work)
                .tabItem {
                    Label("Work Items", systemImage: SFSymbol.List.checklist)
                }
        }
    }
    
    // MARK: - Presentation Panel

    private var presentationPanel: some View {
        VStack(spacing: 0) {
            WorkflowPanelHeader(title: "Presentation Notes")

            Divider()
            
            // Progress Indicator
            WorkflowProgressIndicator(
                totalStudents: students.count,
                studentsWithUnderstanding: studentsWithUnderstanding,
                studentsWithNotes: studentsWithNotes,
                hasGroupObservation: hasGroupObservation
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.primary.opacity(0.03))
            
            Divider()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Status Section
                    presentationStatusSection
                    
                    Divider()
                        .padding(.horizontal, 16)
                    
                    // Group Observation Section
                    groupObservationSection
                    
                    Divider()
                        .padding(.horizontal, 16)
                    
                    // Student Entries Section
                    studentEntriesSection
                }
                .padding(.vertical, 16)
            }
            .dismissKeyboardOnScroll()
        }
        .overlay(alignment: .bottomTrailing) {
            studentNavigatorButton
                .padding(16)
        }
    }
    
    // MARK: - Student Navigator Button
    
    private var studentNavigatorButton: some View {
        Menu {
            ForEach(sortedStudents) { student in
                Button {
                    scrollToStudent(student.id)
                } label: {
                    HStack {
                        Text(StudentFormatter.displayName(for: student))
                        Spacer()
                        if let level = presentationViewModel.entries[student.id]?.understandingLevel {
                            Text("\(level)")
                                .foregroundStyle(UnderstandingLevel.color(for: level))
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "list.bullet.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.white)
                .background(
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 44, height: 44)
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                )
        }
    }
    
    private func scrollToStudent(_ studentID: UUID) {
        // Toggle expansion to ensure student is visible
        if !presentationViewModel.expandedStudentIDs.contains(studentID) {
            presentationViewModel.expandedStudentIDs.insert(studentID)
        }
    }
    
    // MARK: - Presentation Status Section

    private var presentationStatusSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            WorkflowSectionHeader(title: "Presentation Status", icon: "flag.fill")

            HStack(spacing: 12) {
                ForEach(UnifiedPostPresentationSheet.PresentationStatus.allCases) { status in
                    WorkflowStatusButton(
                        icon: status.systemImage,
                        title: status.title,
                        color: status.tint,
                        isSelected: presentationViewModel.status == status,
                        action: { presentationViewModel.status = status }
                    )
                }
            }

            Divider()

            // Apply Understanding to All
            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: "Apply Understanding to All")

                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { level in
                        Button {
                            applyUnderstandingToAll(level: level)
                        } label: {
                            UnderstandingLevelIndicator(level: level, size: 28)
                        }
                        .buttonStyle(.plain)
                        .help(UnderstandingLevel.label(for: level))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Bulk Assignment Section

    private var bulkAssignmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            WorkflowSectionHeader(title: "Quick Assignment", icon: "doc.text.fill")
            
            HStack(spacing: 8) {
                TextField("Set same assignment for all students...", text: $presentationViewModel.bulkAssignment)
                    .textFieldStyle(.roundedBorder)
                
                Button("Apply") {
                    applyBulkAssignment()
                }
                .buttonStyle(.bordered)
                .disabled(presentationViewModel.bulkAssignment.trimmed().isEmpty)
            }
            
            // Default schedule toggles
            HStack(spacing: 16) {
                Toggle("Check-in", isOn: $presentationViewModel.defaultCheckInEnabled)
                    .toggleStyle(.switch)
                    .fixedSize()
                
                if presentationViewModel.defaultCheckInEnabled {
                    DatePicker("", selection: $presentationViewModel.defaultCheckInDate, displayedComponents: .date)
                        .labelsHidden()
                }
                
                Spacer()
                
                Toggle("Due", isOn: $presentationViewModel.defaultDueEnabled)
                    .toggleStyle(.switch)
                    .fixedSize()
                
                if presentationViewModel.defaultDueEnabled {
                    DatePicker("", selection: $presentationViewModel.defaultDueDate, displayedComponents: .date)
                        .labelsHidden()
                }
            }
            .font(.workflowCaption)
            
            // Check-in style picker (only meaningful when multiple students)
            if students.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Check-In Style")
                        .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 8) {
                        ForEach(CheckInStyle.allCases) { style in
                            SelectablePillButton(
                                item: style,
                                isSelected: bulkCheckInStyle == style,
                                color: style.color,
                                icon: style.iconName,
                                label: style.displayName
                            ) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    bulkCheckInStyle = style
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }
    
    private func applyBulkAssignment() {
        // Capture the trimmed text before calling the ViewModel (which clears bulkAssignment)
        var trimmed = presentationViewModel.bulkAssignment.trimmed()
        guard !trimmed.isEmpty else { return }
        
        // Auto-expand "Practice" to include the lesson name and set work kind
        var workKind: WorkKind = .followUpAssignment
        if trimmed.caseInsensitiveCompare("Practice") == .orderedSame {
            trimmed = "Practice: \(lessonName)"
            presentationViewModel.bulkAssignment = trimmed
            workKind = .practiceLesson
        }
        
        presentationViewModel.applyBulkAssignment()
        
        for student in students {
            // Check if this student already has work drafts
            if workDrafts[student.id]?.isEmpty ?? true {
                let draft = createWorkDraft(for: student.id, title: trimmed, kind: workKind, applyDefaultDates: true)
                workDrafts[student.id, default: []].append(draft)
            } else {
                // Update existing first draft
                if let firstIndex = workDrafts[student.id]?.indices.first {
                    workDrafts[student.id]?[firstIndex].title = trimmed
                    
                    // Apply default dates if enabled and not already set
                    if presentationViewModel.defaultCheckInEnabled && workDrafts[student.id]?[firstIndex].checkInDate == nil {
                        workDrafts[student.id]?[firstIndex].checkInDate = presentationViewModel.defaultCheckInDate
                    }
                    if presentationViewModel.defaultDueEnabled && workDrafts[student.id]?[firstIndex].dueDate == nil {
                        workDrafts[student.id]?[firstIndex].dueDate = presentationViewModel.defaultDueDate
                    }
                }
            }
        }
        
        // Show confirmation toast
        withAnimation(.easeInOut(duration: 0.3)) {
            bulkAppliedMessage = "Applied \"\(trimmed)\" to \(students.count) student\(students.count == 1 ? "" : "s")"
            showBulkAppliedToast = true
        }
        Task {
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                // Sleep interrupted, dismiss toast anyway
            }
            withAnimation(.easeInOut(duration: 0.3)) {
                showBulkAppliedToast = false
            }
        }
    }
    
    // MARK: - Student Entries Section

    private var studentEntriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                WorkflowSectionHeader(title: "Student Status & Notes", icon: "person.2.fill")

                Spacer()

                let completed = presentationViewModel.entries.values.filter { !$0.observation.isEmpty || !$0.assignment.isEmpty }.count
                Text("\(completed)/\(presentationViewModel.entries.count)")
                    .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            
            ForEach(sortedStudents, id: \.id) { student in
                studentEntryRow(for: student)
            }
        }
        .padding(.horizontal, 16)
    }
    
    private func studentEntryRow(for student: Student) -> some View {
        let isExpanded = presentationViewModel.expandedStudentIDs.contains(student.id)
        let entry = presentationViewModel.entries[student.id]
        let hasContent = !(entry?.observation.isEmpty ?? true) || !(entry?.assignment.isEmpty ?? true)
        let level = entry?.understandingLevel ?? 3

        return VStack(spacing: 0) {
            // Header row
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isExpanded {
                        presentationViewModel.expandedStudentIDs.remove(student.id)
                    } else {
                        presentationViewModel.expandedStudentIDs.insert(student.id)
                    }
                }
            } label: {
                StudentEntryRowHeader(
                    studentName: StudentFormatter.displayName(for: student),
                    hasContent: hasContent,
                    isExpanded: isExpanded,
                    understandingLevel: level
                )
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                studentExpandedContent(for: student)
            }
        }
    }
    
    @ViewBuilder
    private func studentExpandedContent(for student: Student) -> some View {
        VStack(spacing: 12) {
            // Understanding level picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Understanding")
                    .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                UnderstandingLevelRow(selectedLevel: Binding(
                    get: { presentationViewModel.entries[student.id]?.understandingLevel ?? 3 },
                    set: { presentationViewModel.entries[student.id]?.understandingLevel = $0 }
                ))
            }

            // Observation
            VStack(alignment: .leading, spacing: 6) {
                Text("Observation")
                    .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                TextField("Note about this student...", text: Binding(
                    get: { presentationViewModel.entries[student.id]?.observation ?? "" },
                    set: { presentationViewModel.entries[student.id]?.observation = $0 }
                ), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .padding(.top, -4)
    }
    
    // MARK: - Group Observation Section

    private var groupObservationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            WorkflowSectionHeader(title: "Group Observation", icon: "text.bubble.fill")

            TextField("Notes about the presentation overall...", text: $presentationViewModel.groupObservation, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Work Creation Panel

    private var workCreationPanel: some View {
        VStack(spacing: 0) {
            WorkflowPanelHeader(title: "Work Items")

            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    bulkAssignmentSection
                    
                    ForEach(sortedStudents, id: \.id) { student in
                        studentWorkSection(for: student)
                    }
                }
                .padding(16)
            }
        }
    }
    
    // MARK: - Student Work Section
    
    @ViewBuilder
    private func studentWorkSection(for student: Student) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Student header with context indicators
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(StudentFormatter.displayName(for: student))
                        .font(.system(size: AppTheme.FontSize.body, weight: .bold, design: .rounded))
                    
                    // Quick context from presentation
                    if let entry = presentationViewModel.entries[student.id] {
                        HStack(spacing: 8) {
                            MiniUnderstandingIndicator(level: entry.understandingLevel)

                            if !entry.observation.isEmpty {
                                Image(systemName: "note.text")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                Spacer()
                
                Button {
                    addWorkDraft(for: student.id)
                } label: {
                    Label("Add Work", systemImage: SFSymbol.Action.plusCircleFill)
                        .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                }
                .buttonStyle(.bordered)
            }
            
            // Existing work items from database
            let existingWork = existingWorkItems(for: student.id)
            ForEach(existingWork) { work in
                existingWorkCard(work: work)
            }
            
            // Work drafts (new items being created in this session)
            let drafts = workDrafts[student.id] ?? []
            if drafts.isEmpty && existingWork.isEmpty {
                Text("No work items yet - add one or use bulk assignment")
                    .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                ForEach(drafts) { draft in
                    workDraftCard(draft: draft, studentID: student.id)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
    
    @ViewBuilder
    private func workDraftCard(draft: WorkItemDraft, studentID: UUID) -> some View {
        WorkflowCard {
            VStack(alignment: .leading, spacing: 14) {
                // Title field
                WorkflowTextField(
                    label: "Title",
                    text: Binding(
                        get: { draft.title },
                        set: { newValue in updateWorkDraft(studentID: studentID, draftID: draft.id) { $0.title = newValue } }
                    ),
                    placeholder: "Work Title"
                )

                // Work kind pills
                LabeledFieldSection(label: "Type") {
                    HStack(spacing: 8) {
                        PillButtonGroup(
                            items: WorkKind.allCases,
                            selection: draft.kind,
                            color: { $0.color },
                            icon: { $0.iconName },
                            label: { $0.shortLabel },
                            isSelected: { $0 == draft.kind },
                            onSelect: { kind in
                                updateWorkDraft(studentID: studentID, draftID: draft.id) { $0.kind = kind }
                            }
                        )
                    }
                }

                // Status pills
                LabeledFieldSection(label: "Status") {
                    HStack(spacing: 8) {
                        PillButtonGroup(
                            items: WorkStatus.allCases,
                            selection: draft.status,
                            color: { $0.color },
                            icon: { $0.iconName },
                            label: { $0.displayName },
                            isSelected: { $0 == draft.status },
                            onSelect: { status in
                                updateWorkDraft(studentID: studentID, draftID: draft.id) { $0.status = status }
                            }
                        )
                        Spacer()
                    }
                }

                // Dates
                WorkDatesRow(
                    checkInDate: Binding(
                        get: { draft.checkInDate },
                        set: { newValue in updateWorkDraft(studentID: studentID, draftID: draft.id) { $0.checkInDate = newValue } }
                    ),
                    dueDate: Binding(
                        get: { draft.dueDate },
                        set: { newValue in updateWorkDraft(studentID: studentID, draftID: draft.id) { $0.dueDate = newValue } }
                    ),
                    defaultCheckInDate: presentationViewModel.defaultCheckInDate,
                    defaultDueDate: presentationViewModel.defaultDueDate
                )

                // Notes field
                WorkflowTextField(
                    label: "Notes",
                    text: Binding(
                        get: { draft.notes },
                        set: { newValue in updateWorkDraft(studentID: studentID, draftID: draft.id) { $0.notes = newValue } }
                    ),
                    placeholder: "Add notes...",
                    axis: .vertical,
                    lineLimit: 2...
                )

                // Completion details (if complete)
                if draft.status == .complete {
                    workDraftCompletionSection(draft: draft, studentID: studentID)
                }

                // Bottom actions
                HStack {
                    WorkflowInfoHint(text: "Full editor available after saving")
                    Spacer()
                    WorkflowDeleteButton {
                        removeWorkDraft(studentID: studentID, draftID: draft.id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func workDraftCompletionSection(draft: WorkItemDraft, studentID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ExpandableSectionButton(
                title: "Completion Details",
                isExpanded: draft.showMoreDetails,
                action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        updateWorkDraft(studentID: studentID, draftID: draft.id) {
                            $0.showMoreDetails.toggle()
                        }
                    }
                }
            )

            if draft.showMoreDetails {
                VStack(alignment: .leading, spacing: 12) {
                    // Outcome picker
                    LabeledFieldSection(label: "Outcome") {
                        FlowLayout(spacing: 8) {
                            PillButtonGroup(
                                items: CompletionOutcome.allCases,
                                selection: draft.completionOutcome,
                                color: { $0.color },
                                icon: { $0.iconName },
                                label: { $0.displayName },
                                isSelected: { $0 == draft.completionOutcome },
                                onSelect: { outcome in
                                    updateWorkDraft(studentID: studentID, draftID: draft.id) { $0.completionOutcome = outcome }
                                }
                            )
                        }
                    }

                    // Completion note
                    WorkflowTextField(
                        label: "Completion Note",
                        text: Binding(
                            get: { draft.completionNote },
                            set: { newValue in updateWorkDraft(studentID: studentID, draftID: draft.id) { $0.completionNote = newValue } }
                        ),
                        placeholder: "Add completion note...",
                        axis: .vertical,
                        lineLimit: 2...
                    )
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .cardBackground(color: Color.green.opacity(0.08), cornerRadius: 10)
    }
    
    // MARK: - Existing Work Card

    @ViewBuilder
    private func existingWorkCard(work: WorkModel) -> some View {
        WorkflowCard(
            backgroundColor: Color.blue.opacity(0.06),
            borderColor: Color.blue.opacity(0.2)
        ) {
            VStack(alignment: .leading, spacing: 12) {
                // Title
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(work.title.isEmpty ? lessonName : work.title)
                            .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))

                        Text("Created \(work.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    WorkflowBadge(
                        icon: work.status.iconName,
                        text: work.status.displayName,
                        color: work.status.color
                    )
                }

                // Work kind badge
                if let kind = work.kind {
                    WorkflowBadge(
                        icon: kind.iconName,
                        text: kind.shortLabel,
                        color: kind.color
                    )
                }

                // Due date if set
                if let dueAt = work.dueAt {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 10))
                        Text("Due: \(dueAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
    

    
    // MARK: - Work Draft Management
    
    private func addWorkDraft(for studentID: UUID) {
        let assignment = presentationViewModel.entries[studentID]?.assignment ?? ""
        let draft = createWorkDraft(for: studentID, title: assignment)
        workDrafts[studentID, default: []].append(draft)
    }
    
    private func createWorkDraft(for studentID: UUID, title: String = "", kind: WorkKind = .followUpAssignment, applyDefaultDates: Bool = false) -> WorkItemDraft {
        var draft = WorkItemDraft(studentID: studentID, title: title.isEmpty ? "" : title, kind: kind, checkInStyle: bulkCheckInStyle)
        
        if applyDefaultDates {
            if presentationViewModel.defaultCheckInEnabled {
                draft.checkInDate = presentationViewModel.defaultCheckInDate
            }
            if presentationViewModel.defaultDueEnabled {
                draft.dueDate = presentationViewModel.defaultDueDate
            }
        }
        
        return draft
    }
    
    private func removeWorkDraft(studentID: UUID, draftID: UUID) {
        workDrafts[studentID]?.removeAll { $0.id == draftID }
    }
    
    private func updateWorkDraft(studentID: UUID, draftID: UUID, update: (inout WorkItemDraft) -> Void) {
        guard let index = workDrafts[studentID]?.firstIndex(where: { $0.id == draftID }) else { return }
        update(&workDrafts[studentID]![index])
    }
    

    private func syncAssignmentToWorkDraft(studentID: UUID, assignment: String) {
        let trimmedAssignment = assignment.trimmed()
        
        if workDrafts[studentID]?.isEmpty ?? true {
            if !trimmedAssignment.isEmpty {
                let draft = createWorkDraft(for: studentID, title: trimmedAssignment)
                workDrafts[studentID, default: []].append(draft)
            }
        } else if let firstIndex = workDrafts[studentID]?.indices.first {
            workDrafts[studentID]?[firstIndex].title = trimmedAssignment
        }
    }
    
    // MARK: - Completion
    
    func completeWorkflow() {
        isSaving = true
        
        // 1. Unlock next lessons if needed
        presentationViewModel.unlockNextLessonsIfNeeded(
            lessonID: lessonID,
            modelContext: modelContext,
            lessons: lessons,
            lessonAssignments: lessonAssignments
        )
        
        // 2. Create work items
        let repository = WorkRepository(context: modelContext)
        
        for (studentID, drafts) in workDrafts {
            for draft in drafts where !draft.title.isEmpty {
                
                do {
                    let work = try repository.createWork(
                        studentID: studentID,
                        lessonID: lessonID,
                        title: draft.title,
                        kind: draft.kind,
                        scheduledDate: draft.dueDate
                    )

                    // Update status, notes, check-in style, and completion details after creation
                    work.status = draft.status
                    work.checkInStyle = draft.checkInStyle

                    // Combine notes and completion note if present
                    var allNotes = draft.notes
                    if draft.status == .complete && !draft.completionNote.isEmpty {
                        if !allNotes.isEmpty {
                            allNotes += "\n\nCompletion: " + draft.completionNote
                        } else {
                            allNotes = "Completion: " + draft.completionNote
                        }
                    }
                    if !allNotes.isEmpty {
                        work.setLegacyNoteText(allNotes, in: modelContext)
                    }

                    // Set completion outcome if status is complete
                    if draft.status == .complete, let outcome = draft.completionOutcome {
                        work.completionOutcome = outcome
                    }
                } catch {
                    Self.logger.warning("Failed to create work item: \(error)")
                }
            }
        }
        
        // 3. Save everything
        saveCoordinator.save(modelContext, reason: "Unified Presentation Workflow")
        
        onComplete()
    }
    
    // MARK: - Helpers
    
    private func applyUnderstandingToAll(level: Int) {
        var count = 0
        for student in students {
            if presentationViewModel.entries[student.id] != nil {
                presentationViewModel.entries[student.id]?.understandingLevel = level
                count += 1
            }
        }
        
        // Show toast notification
        withAnimation(.easeInOut(duration: 0.3)) {
            bulkAppliedMessage = "Applied \(UnderstandingLevel.label(for: level)) to \(count) student\(count == 1 ? "" : "s")"
            showBulkAppliedToast = true
        }
        
        // Auto-hide after 2 seconds
        Task {
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                Self.logger.debug("Toast auto-hide interrupted: \(error)")
            }
            withAnimation(.easeInOut(duration: 0.3)) {
                showBulkAppliedToast = false
            }
        }
    }
    
}
