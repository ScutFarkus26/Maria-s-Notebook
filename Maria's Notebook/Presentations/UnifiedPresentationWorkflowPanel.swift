import SwiftUI
import SwiftData
import OSLog

/// Reusable panel component for presentation workflow (can be used in sheets or embedded)
/// Contains the split-panel UI for presentation notes and work item creation
struct UnifiedPresentationWorkflowPanel: View {
    // MARK: - Types
    
    struct WorkItemDraft: Identifiable {
        let id: UUID
        let studentID: UUID
        var title: String
        var kind: WorkKind
        var checkInDate: Date?
        var dueDate: Date?
        var notes: String
        
        init(studentID: UUID, title: String = "", kind: WorkKind = .practiceLesson) {
            self.id = UUID()
            self.studentID = studentID
            self.title = title
            self.kind = kind
            self.checkInDate = nil
            self.dueDate = nil
            self.notes = ""
        }
    }
    
    // MARK: - Input
    
    @ObservedObject var presentationViewModel: PostPresentationFormViewModel
    let students: [Student]
    let lessonName: String
    let lessonID: UUID
    let onComplete: () -> Void
    let onCancel: () -> Void
    
    // Optional binding to trigger completion from external toolbar (for sheet context)
    var triggerCompletion: Binding<Bool>?
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator
    
    @Query(sort: \Lesson.sortIndex) private var lessons: [Lesson]
    @Query private var studentLessons: [StudentLesson]
    
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
    @Namespace private var studentScrollAnchor
    
    private enum PanelFocus {
        case presentation
        case work
    }
    
    // MARK: - Computed
    
    private var sortedStudents: [Student] {
        students.sorted(by: StudentSortComparator.byFirstName)
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
                .font(.system(size: AppTheme.FontSize.callout, weight: .medium, design: .rounded))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        )
    }
    
    // MARK: - Progress Indicator
    
    private var progressIndicator: some View {
        VStack(spacing: 6) {
            HStack(spacing: 16) {
                // Understanding progress
                HStack(spacing: 6) {
                    Image(systemName: studentsWithUnderstanding == students.count ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(studentsWithUnderstanding == students.count ? .green : .secondary)
                        .font(.system(size: 14))
                    Text("\(studentsWithUnderstanding)/\(students.count) understanding set")
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                
                // Notes progress
                HStack(spacing: 6) {
                    Image(systemName: studentsWithNotes > 0 ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(studentsWithNotes > 0 ? .green : .secondary)
                        .font(.system(size: 14))
                    Text("\(studentsWithNotes)/\(students.count) with notes")
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                
                // Group observation
                HStack(spacing: 6) {
                    Image(systemName: hasGroupObservation ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(hasGroupObservation ? .green : .secondary)
                        .font(.system(size: 14))
                    Text("Group notes")
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 6)
                    
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * progressPercentage, height: 6)
                }
            }
            .frame(height: 6)
        }
    }
    
    private var progressPercentage: Double {
        let totalItems = 3.0 // understanding, notes, group observation
        var completed = 0.0
        
        if studentsWithUnderstanding == students.count {
            completed += 1.0
        }
        if studentsWithNotes > 0 {
            completed += 1.0
        }
        if hasGroupObservation {
            completed += 1.0
        }
        
        return completed / totalItems
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
                    Label("Presentation", systemImage: "book.fill")
                }
            
            workCreationPanel
                .tag(PanelFocus.work)
                .tabItem {
                    Label("Work Items", systemImage: "checklist")
                }
        }
    }
    
    // MARK: - Presentation Panel
    
    private var presentationPanel: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Presentation Notes")
                    .font(.system(size: AppTheme.FontSize.titleSmall, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(.bar)
            
            Divider()
            
            // Progress Indicator
            progressIndicator
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
                                .foregroundStyle(understandingColor(for: level))
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
            Label("Presentation Status", systemImage: "flag.fill")
                .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            
            HStack(spacing: 12) {
                ForEach(UnifiedPostPresentationSheet.PresentationStatus.allCases) { status in
                    statusButton(for: status)
                }
            }
            
            Divider()
            
            // Apply Understanding to All
            VStack(alignment: .leading, spacing: 8) {
                Text("Apply Understanding to All")
                    .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { level in
                        Button {
                            applyUnderstandingToAll(level: level)
                        } label: {
                            Circle()
                                .fill(understandingColor(for: level))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Text("\(level)")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(understandingLabel(for: level))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }
    
    private func statusButton(for status: UnifiedPostPresentationSheet.PresentationStatus) -> some View {
        Button {
            presentationViewModel.status = status
        } label: {
            HStack(spacing: 8) {
                Image(systemName: status.systemImage)
                Text(status.title)
            }
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .foregroundStyle(status.tint)
            .background(
                Capsule(style: .continuous)
                    .fill(status.tint.opacity(presentationViewModel.status == status ? 0.20 : 0.10))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(status.tint.opacity(presentationViewModel.status == status ? 0.5 : 0.25), lineWidth: presentationViewModel.status == status ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Bulk Assignment Section
    
    private var bulkAssignmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Quick Assignment", systemImage: "doc.text.fill")
                .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            
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
            .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
        }
        .padding(.horizontal, 16)
    }
    
    private func applyBulkAssignment() {
        presentationViewModel.applyBulkAssignment()
        
        // Also create/update work drafts for all students
        let trimmed = presentationViewModel.bulkAssignment.trimmed()
        guard !trimmed.isEmpty else { return }
        
        for student in students {
            // Check if this student already has work drafts
            if workDrafts[student.id]?.isEmpty ?? true {
                // Create new draft
                var draft = WorkItemDraft(
                    studentID: student.id,
                    title: trimmed,
                    kind: .followUpAssignment
                )
                
                // Apply default dates if enabled
                if presentationViewModel.defaultCheckInEnabled {
                    draft.checkInDate = presentationViewModel.defaultCheckInDate
                }
                if presentationViewModel.defaultDueEnabled {
                    draft.dueDate = presentationViewModel.defaultDueDate
                }
                
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
    }
    
    // MARK: - Student Entries Section
    
    private var studentEntriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Student Status & Notes", systemImage: "person.2.fill")
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                
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
        
        return VStack(spacing: 0) {
            // Header row
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        presentationViewModel.expandedStudentIDs.remove(student.id)
                    } else {
                        presentationViewModel.expandedStudentIDs.insert(student.id)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Text(StudentFormatter.displayName(for: student))
                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    // Understanding level indicator
                    understandingIndicator(for: student.id)
                    
                    HStack(spacing: 4) {
                        if hasContent {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.system(size: 14))
                        }
                        
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: isExpanded ? 12 : 8, style: .continuous)
                        .fill(Color.primary.opacity(isExpanded ? 0.06 : 0.03))
                )
                .contentShape(Rectangle())
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
                
                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { level in
                        Button {
                            presentationViewModel.entries[student.id]?.understandingLevel = level
                        } label: {
                            Circle()
                                .fill(understandingColor(for: level).opacity(
                                    (presentationViewModel.entries[student.id]?.understandingLevel ?? 3) >= level ? 1.0 : 0.2
                                ))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer()
                    
                    Text(understandingLabel(for: presentationViewModel.entries[student.id]?.understandingLevel ?? 3))
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
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
    
    private func understandingIndicator(for studentID: UUID) -> some View {
        let level = presentationViewModel.entries[studentID]?.understandingLevel ?? 3
        return HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Circle()
                    .fill(understandingColor(for: level).opacity(i <= level ? 1.0 : 0.2))
                    .frame(width: 8, height: 8)
            }
        }
    }
    
    // MARK: - Group Observation Section
    
    private var groupObservationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Group Observation", systemImage: "text.bubble.fill")
                .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            
            TextField("Notes about the presentation overall...", text: $presentationViewModel.groupObservation, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Work Creation Panel
    
    private var workCreationPanel: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Work Items")
                    .font(.system(size: AppTheme.FontSize.titleSmall, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(.bar)
            
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
                            // Understanding indicator
                            HStack(spacing: 2) {
                                ForEach(1...5, id: \.self) { level in
                                    Circle()
                                        .fill(understandingColor(for: level).opacity(
                                            entry.understandingLevel >= level ? 1.0 : 0.2
                                        ))
                                        .frame(width: 6, height: 6)
                                }
                            }
                            
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
                    Label("Add Work", systemImage: "plus.circle.fill")
                        .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                }
                .buttonStyle(.bordered)
            }
            
            // Existing work drafts
            let drafts = workDrafts[student.id] ?? []
            if drafts.isEmpty {
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
        VStack(alignment: .leading, spacing: 10) {
            // Title and remove button
            HStack {
                TextField("Work title", text: Binding(
                    get: { draft.title },
                    set: { newTitle in
                        updateWorkDraft(studentID: studentID, draftID: draft.id) { $0.title = newTitle }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                
                Button {
                    removeWorkDraft(studentID: studentID, draftID: draft.id)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
            
            // Work kind picker
            Picker("Type", selection: Binding(
                get: { draft.kind },
                set: { newKind in
                    updateWorkDraft(studentID: studentID, draftID: draft.id) { $0.kind = newKind }
                }
            )) {
                Text("Practice").tag(WorkKind.practiceLesson)
                Text("Follow-Up").tag(WorkKind.followUpAssignment)
                Text("Project").tag(WorkKind.research)
                Text("Report").tag(WorkKind.report)
            }
            .pickerStyle(.segmented)
            
            // Dates
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Check-in")
                        .font(.system(size: AppTheme.FontSize.captionSmall, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 4) {
                        Button {
                            toggleCheckInDate(studentID: studentID, draftID: draft.id)
                        } label: {
                            Image(systemName: draft.checkInDate != nil ? "checkmark.square.fill" : "square")
                                .foregroundStyle(draft.checkInDate != nil ? .blue : .secondary)
                        }
                        .buttonStyle(.plain)
                        
                        if draft.checkInDate != nil {
                            DatePicker("", selection: Binding(
                                get: { draft.checkInDate ?? Date() },
                                set: { newDate in
                                    updateWorkDraft(studentID: studentID, draftID: draft.id) { $0.checkInDate = newDate }
                                }
                            ), displayedComponents: .date)
                            .labelsHidden()
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Due Date")
                        .font(.system(size: AppTheme.FontSize.captionSmall, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 4) {
                        Button {
                            toggleDueDate(studentID: studentID, draftID: draft.id)
                        } label: {
                            Image(systemName: draft.dueDate != nil ? "checkmark.square.fill" : "square")
                                .foregroundStyle(draft.dueDate != nil ? .blue : .secondary)
                        }
                        .buttonStyle(.plain)
                        
                        if draft.dueDate != nil {
                            DatePicker("", selection: Binding(
                                get: { draft.dueDate ?? Date() },
                                set: { newDate in
                                    updateWorkDraft(studentID: studentID, draftID: draft.id) { $0.dueDate = newDate }
                                }
                            ), displayedComponents: .date)
                            .labelsHidden()
                        }
                    }
                }
                
                Spacer()
            }
            
            // Notes
            TextField("Notes (optional)", text: Binding(
                get: { draft.notes },
                set: { newNotes in
                    updateWorkDraft(studentID: studentID, draftID: draft.id) { $0.notes = newNotes }
                }
            ), axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(2...4)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
    
    // MARK: - Work Draft Management
    
    private func addWorkDraft(for studentID: UUID) {
        // Initialize with assignment from presentation if available
        let assignment = presentationViewModel.entries[studentID]?.assignment ?? ""
        let draft = WorkItemDraft(
            studentID: studentID,
            title: assignment.isEmpty ? "" : assignment,
            kind: .followUpAssignment
        )
        workDrafts[studentID, default: []].append(draft)
    }
    
    private func removeWorkDraft(studentID: UUID, draftID: UUID) {
        workDrafts[studentID]?.removeAll { $0.id == draftID }
    }
    
    private func updateWorkDraft(studentID: UUID, draftID: UUID, update: (inout WorkItemDraft) -> Void) {
        guard let index = workDrafts[studentID]?.firstIndex(where: { $0.id == draftID }) else { return }
        update(&workDrafts[studentID]![index])
    }
    
    private func toggleCheckInDate(studentID: UUID, draftID: UUID) {
        guard let index = workDrafts[studentID]?.firstIndex(where: { $0.id == draftID }) else { return }
        if workDrafts[studentID]![index].checkInDate != nil {
            workDrafts[studentID]![index].checkInDate = nil
        } else {
            workDrafts[studentID]![index].checkInDate = presentationViewModel.defaultCheckInDate
        }
    }
    
    private func toggleDueDate(studentID: UUID, draftID: UUID) {
        guard let index = workDrafts[studentID]?.firstIndex(where: { $0.id == draftID }) else { return }
        if workDrafts[studentID]![index].dueDate != nil {
            workDrafts[studentID]![index].dueDate = nil
        } else {
            workDrafts[studentID]![index].dueDate = presentationViewModel.defaultDueDate
        }
    }
    
    private func syncAssignmentToWorkDraft(studentID: UUID, assignment: String) {
        let trimmedAssignment = assignment.trimmed()
        
        // If no work drafts exist for this student, create one
        if workDrafts[studentID]?.isEmpty ?? true {
            if !trimmedAssignment.isEmpty {
                let draft = WorkItemDraft(
                    studentID: studentID,
                    title: trimmedAssignment,
                    kind: .followUpAssignment
                )
                workDrafts[studentID, default: []].append(draft)
            }
        } else {
            // Update the first draft's title
            if let firstIndex = workDrafts[studentID]?.indices.first {
                workDrafts[studentID]?[firstIndex].title = trimmedAssignment
            }
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
            studentLessons: studentLessons
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
                    
                    // Update notes after creation if present
                    if !draft.notes.isEmpty {
                        work.notes = draft.notes
                    }
                } catch {
                    Logger.app(category: "UnifiedPresentationWorkflow").error("Failed to create work item: \(error)")
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
            bulkAppliedMessage = "Applied \(understandingLabel(for: level)) to \(count) student\(count == 1 ? "" : "s")"
            showBulkAppliedToast = true
        }
        
        // Auto-hide after 2 seconds
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeInOut(duration: 0.3)) {
                showBulkAppliedToast = false
            }
        }
    }
    
    private func understandingColor(for level: Int) -> Color {
        switch level {
        case 1: return .red
        case 2: return .orange
        case 3: return .yellow
        case 4: return .green
        case 5: return .blue
        default: return .gray
        }
    }
    
    private func understandingLabel(for level: Int) -> String {
        switch level {
        case 1: return "Struggling"
        case 2: return "Needs Support"
        case 3: return "Developing"
        case 4: return "Proficient"
        case 5: return "Mastered"
        default: return ""
        }
    }
}
