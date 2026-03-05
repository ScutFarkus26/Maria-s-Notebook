// QuickNewWorkItemSheet.swift
// Quick creation sheet for new work items

import SwiftUI
import SwiftData

struct QuickNewWorkItemSheet: View {
    /// Optional callback when work is created and user wants to view details immediately
    var onCreatedAndOpen: ((UUID) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    // Test student filtering
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames) private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    @Query(sort: [SortDescriptor(\Lesson.subject), SortDescriptor(\Lesson.sortIndex)])
    private var allLessons: [Lesson]

    @Query(sort: Student.sortByName)
    private var allStudentsRaw: [Student]
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Filter out test students when setting is disabled
    private var allStudents: [Student] {
        TestStudentsFilter.filterVisible(allStudentsRaw.uniqueByID, show: showTestStudents, namesRaw: testStudentNamesRaw)
    }

    @State private var selectedLessonID: UUID?
    @State private var selectedStudentIDs: Set<UUID> = []
    @State private var workTitle: String = ""
    @State private var workKind: WorkKind = .practiceLesson
    @State private var dueDate: Date?
    @State private var hasDueDate: Bool = false
    @State private var lessonSearchText: String = ""
    @State private var isSaving: Bool = false
    
    // Check-in states
    @State private var hasCheckIn: Bool = false
    @State private var checkInDate: Date = Date()
    @State private var checkInReason: CheckInMigrationService.CheckInReason = .progressCheck
    @State private var checkInStyle: CheckInStyle = .flexible

    // Popover states
    @State private var showingLessonPopover: Bool = false
    @State private var showingStudentPopover: Bool = false
    @FocusState private var lessonFieldFocused: Bool

    private var filteredLessons: [Lesson] {
        let query = lessonSearchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return allLessons }
        return allLessons.filter {
            $0.name.lowercased().contains(query) ||
            $0.subject.lowercased().contains(query) ||
            $0.group.lowercased().contains(query)
        }
    }

    private var selectedLesson: Lesson? {
        guard let id = selectedLessonID else { return nil }
        return allLessons.first { $0.id == id }
    }

    private var selectedStudents: [Student] {
        allStudents.filter { selectedStudentIDs.contains($0.id) }
    }

    private var canSave: Bool {
        selectedLessonID != nil && !selectedStudentIDs.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    Text("New Work")
                        .font(AppTheme.ScaledFont.titleXLarge)

                    // Lesson Section
                    lessonSection()

                    Divider()

                    // Student Section
                    studentSection()

                    Divider()

                    // Details Section
                    detailsSection()
                }
                .padding(AppTheme.Spacing.large)
            }

            Divider()

            // Bottom bar
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                if onCreatedAndOpen != nil && selectedStudentIDs.count == 1 {
                    Button("Create & Open") { saveWorkItem(andOpen: true) }
                        .disabled(!canSave || isSaving)
                }
                Button("Create") { saveWorkItem(andOpen: false) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave || isSaving)
            }
            .padding(AppTheme.Spacing.medium)
            .background(.bar)
        }
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #else
        .frame(minWidth: UIConstants.SheetSize.medium.width, minHeight: UIConstants.SheetSize.medium.height)
        #endif
    }

    // MARK: - Lesson Section

    @ViewBuilder
    private func lessonSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lesson")
                .font(.headline)

            // Search field with popover
            TextField("Search lessons...", text: $lessonSearchText)
                .textFieldStyle(.roundedBorder)
                .focused($lessonFieldFocused)
                .onChange(of: lessonSearchText) { _, newValue in
                    if !newValue.trimmed().isEmpty {
                        showingLessonPopover = true
                    }
                }
                .onSubmit {
                    // If user typed an exact lesson name, select it
                    let trimmed = lessonSearchText.trimmed()
                    if let match = filteredLessons.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                        selectLesson(match)
                    }
                }
                .onTapGesture {
                    showingLessonPopover = true
                }
                .popover(isPresented: $showingLessonPopover, arrowEdge: .bottom) {
                    lessonPopoverContent()
                }

            // Selected lesson display
            if let lesson = selectedLesson {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lesson.name)
                            .font(.subheadline.weight(.semibold))
                        if !lesson.subject.isEmpty {
                            Text(lesson.subject)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        selectedLessonID = nil
                        lessonSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(AppTheme.Spacing.compact)
                .background(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
                .cornerRadius(UIConstants.CornerRadius.medium)
            } else {
                Text("Choose a lesson to continue.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func lessonPopoverContent() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            List(filteredLessons.prefix(15), id: \.id) { lesson in
                Button {
                    selectLesson(lesson)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lesson.name)
                                .foregroundStyle(.primary)
                            if !lesson.subject.isEmpty {
                                Text("\(lesson.subject) • \(lesson.group)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if selectedLessonID == lesson.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            #if os(macOS)
            .focusable(false)
            #endif
        }
        .padding(AppTheme.Spacing.small)
        #if os(macOS)
        .frame(minWidth: UIConstants.SheetSize.compact.width, minHeight: 300)
        #else
        .frame(minHeight: 300)
        #endif
    }

    private func selectLesson(_ lesson: Lesson) {
        selectedLessonID = lesson.id
        lessonSearchText = lesson.name
        showingLessonPopover = false
        lessonFieldFocused = false

        // Auto-set work title if empty
        if workTitle.isEmpty {
            workTitle = lesson.name
        }
    }

    // MARK: - Student Section

    private func removeStudent(id: UUID) {
        _ = adaptiveWithAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            selectedStudentIDs.remove(id)
        }
    }

    @ViewBuilder
    private func studentChip(for student: Student) -> some View {
        HStack(spacing: 4) {
            Text(StudentFormatter.displayName(for: student))
                .font(AppTheme.ScaledFont.bodySemibold)
                .padding(.horizontal, AppTheme.Spacing.compact)
                .padding(.vertical, AppTheme.Spacing.verySmall)
                .background(Color.accentColor.opacity(UIConstants.OpacityConstants.accent))
                .foregroundStyle(Color.accentColor)
                .clipShape(Capsule())

            Button {
                removeStudent(id: student.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func studentSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Student")
                .font(.headline)

            HStack(alignment: .center, spacing: 8) {
                // Selected students as chips
                if !selectedStudents.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(selectedStudents) { student in
                                studentChip(for: student)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                // Add student button
                Button {
                    showingStudentPopover = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingStudentPopover, arrowEdge: .bottom) {
                    StudentPickerPopover(
                        students: allStudents,
                        selectedIDs: $selectedStudentIDs,
                        onDone: { showingStudentPopover = false }
                    )
                }
            }
            .adaptiveAnimation(.spring(response: 0.25, dampingFraction: 0.85), value: selectedStudentIDs)

            if selectedStudentIDs.isEmpty {
                Text("Add at least one student.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Details Section

    @ViewBuilder
    private func detailsSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)

            TextField("Title (optional)", text: $workTitle)
                .textFieldStyle(.roundedBorder)

            // Work Kind picker as segmented buttons
            HStack(spacing: 0) {
                kindButton(.practiceLesson, "Practice")
                kindButton(.followUpAssignment, "Follow-Up")
                kindButton(.research, "Project")
                kindButton(.report, "Report")
            }
            .background(RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium).stroke(Color.primary.opacity(UIConstants.OpacityConstants.light)))

            // Due date toggle and picker
            Toggle("Set due date", isOn: $hasDueDate)
                .onChange(of: hasDueDate) { _, newValue in
                    if newValue {
                        if dueDate == nil {
                            dueDate = AppCalendar.startOfDay(Date())
                        }
                    } else {
                        dueDate = nil
                    }
                }

            if hasDueDate {
                DatePicker("Due date", selection: Binding(
                    get: { dueDate ?? AppCalendar.startOfDay(Date()) },
                    set: { dueDate = $0 }
                ), displayedComponents: .date)
            }
            
            Divider()
                .padding(.vertical, 8)
            
            // Check-in toggle and controls
            Toggle("Schedule check-in", isOn: $hasCheckIn)
                .onChange(of: hasCheckIn) { _, newValue in
                    if newValue {
                        checkInDate = AppCalendar.startOfDay(Date())
                    }
                }
            
            if hasCheckIn {
                HStack(spacing: 12) {
                    DatePicker("Check-in date", selection: $checkInDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                    
                    Menu {
                        ForEach(CheckInMigrationService.CheckInReason.allCases) { reason in
                            Button {
                                checkInReason = reason
                            } label: {
                                HStack {
                                    Image(systemName: legacyReasonIcon(reason))
                                    Text(legacyReasonLabel(reason))
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: legacyReasonIcon(checkInReason))
                                .font(.system(size: 12, weight: .medium))
                            Text(legacyReasonLabel(checkInReason))
                                .font(AppTheme.ScaledFont.captionSemibold)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, AppTheme.Spacing.compact)
                        .padding(.vertical, AppTheme.Spacing.small)
                        .background(
                            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium)
                                .fill(Color.primary.opacity(UIConstants.OpacityConstants.subtle))
                        )
                    }
                }
            }
            
            // Check-in style picker (only shown when multiple students selected)
            if selectedStudentIDs.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Check-In Style")
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 8) {
                        ForEach(CheckInStyle.allCases) { style in
                            SelectablePillButton(
                                item: style,
                                isSelected: checkInStyle == style,
                                color: style.color,
                                icon: style.iconName,
                                label: style.displayName
                            ) {
                                adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    checkInStyle = style
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func kindButton(_ kind: WorkKind, _ label: String) -> some View {
        Button(label) {
            workKind = kind
        }
        .padding(.horizontal, AppTheme.Spacing.compact)
        .padding(.vertical, AppTheme.Spacing.small)
        .background(workKind == kind ? Color.accentColor.opacity(UIConstants.OpacityConstants.light) : Color.clear)
        .foregroundStyle(workKind == kind ? Color.accentColor : .primary)
        .font(.subheadline)
    }

    // MARK: - Save

    private func saveWorkItem(andOpen: Bool) {
        guard let lessonID = selectedLessonID,
              !selectedStudentIDs.isEmpty else { return }
        isSaving = true

        let repository = WorkRepository(context: modelContext)

        do {
            var createdWorkID: UUID?
            // Create work for each selected student
            for studentID in selectedStudentIDs {
                let work = try repository.createWork(
                    studentID: studentID,
                    lessonID: lessonID,
                    title: workTitle.isEmpty ? nil : workTitle,
                    kind: workKind,
                    scheduledDate: hasDueDate ? dueDate : nil
                )
                
                // Set check-in style for multi-student work
                if selectedStudentIDs.count > 1 {
                    work.checkInStyle = checkInStyle
                }
                
                // Create check-in if scheduled
                if hasCheckIn {
                    let normalized = AppCalendar.startOfDay(checkInDate)
                    
                    // Create WorkCheckIn for scheduled check-ins
                    let checkIn = WorkCheckIn(
                        workID: work.id,
                        date: normalized,
                        status: .scheduled,
                        purpose: CheckInMigrationService.mapReasonToPurpose(checkInReason)
                    )
                    modelContext.insert(checkIn)
                }
                
                // Keep reference to first created work for "Create & Open"
                if createdWorkID == nil {
                    createdWorkID = work.id
                }
            }
            saveCoordinator.save(modelContext, reason: "Quick New Work Item")
            dismiss()

            // If user wants to open the detail view, call the callback after dismiss
            if andOpen, let workID = createdWorkID {
                onCreatedAndOpen?(workID)
            }
        } catch {
            isSaving = false
        }
    }
    
    // MARK: - Check-In Reason Helpers
    
    private func legacyReasonIcon(_ reason: CheckInMigrationService.CheckInReason) -> String {
        switch reason {
        case .progressCheck: return "checkmark.circle"
        case .dueDate: return "calendar.badge.exclamationmark"
        case .assessment: return "doc.text.magnifyingglass"
        case .followUp: return "arrow.turn.up.right"
        case .studentRequest: return "person.bubble"
        case .other: return "ellipsis.circle"
        }
    }
    
    private func legacyReasonLabel(_ reason: CheckInMigrationService.CheckInReason) -> String {
        switch reason {
        case .progressCheck: return "Progress Check"
        case .dueDate: return "Due Date"
        case .assessment: return "Assessment"
        case .followUp: return "Follow Up"
        case .studentRequest: return "Student Request"
        case .other: return "Other"
        }
    }
}
