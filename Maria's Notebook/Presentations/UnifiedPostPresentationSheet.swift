import SwiftUI
import SwiftData

/// Unified sheet for recording a presentation with per-student notes, assignments, and group observations.
/// This sheet stays open until the user clicks Done AND the status is valid (Just Presented or Previously Presented).
struct UnifiedPostPresentationSheet: View {
    // MARK: - Types

    struct StudentEntry: Identifiable {
        let id: UUID // student ID
        let name: String
        var understandingLevel: Int = 3 // 1-5 scale
        var observation: String = ""
        var assignment: String = ""
        var checkInDate: Date?
        var dueDate: Date?
    }

    enum PresentationStatus: String, CaseIterable, Identifiable {
        case justPresented
        case previouslyPresented
        case needsAnother

        var id: String { rawValue }

        var title: String {
            switch self {
            case .justPresented: return "Just Presented"
            case .previouslyPresented: return "Previously Presented"
            case .needsAnother: return "Needs Another"
            }
        }

        var systemImage: String {
            switch self {
            case .justPresented: return "checkmark.circle.fill"
            case .previouslyPresented: return "clock.badge.checkmark"
            case .needsAnother: return "arrow.clockwise.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .justPresented, .previouslyPresented: return .green
            case .needsAnother: return .orange
            }
        }
    }

    // MARK: - Input

    let students: [Student]
    let lessonName: String
    let lessonID: UUID?
    let initialStatus: PresentationStatus

    // MARK: - Callbacks

    var onDone: (PresentationStatus, [StudentEntry], String) -> Void
    var onCancel: () -> Void

    // MARK: - State

    @StateObject private var viewModel: PostPresentationFormViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Lesson.sortIndex) private var lessons: [Lesson]
    @Query private var studentLessons: [StudentLesson]

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    // MARK: - Init

    init(
        students: [Student],
        lessonName: String,
        lessonID: UUID? = nil,
        initialStatus: PresentationStatus = .justPresented,
        onDone: @escaping (PresentationStatus, [StudentEntry], String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        let deduped = students.uniqueByID
        self.students = deduped
        self.lessonName = lessonName
        self.lessonID = lessonID
        self.initialStatus = initialStatus
        self.onDone = onDone
        self.onCancel = onCancel

        // Initialize ViewModel
        _viewModel = StateObject(wrappedValue: PostPresentationFormViewModel(students: deduped, initialStatus: initialStatus))
    }

    // MARK: - Computed

    private var canDismiss: Bool {
        viewModel.canDismiss
    }

    private var sortedStudents: [Student] {
        students.sorted { $0.firstName.localizedCaseInsensitiveCompare($1.firstName) == .orderedAscending }
    }
    
    private var suggestedWorkItems: [String] {
        guard let lessonID = lessonID else { return [] }
        guard let lesson = lessons.first(where: { $0.id == lessonID }) else { return [] }
        return lesson.suggestedFollowUpWorkItems
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Content
            ScrollView {
                VStack(spacing: 20) {
                    // Status Section
                    statusSection

                    Divider()
                        .padding(.horizontal, 16)

                    // Bulk Assignment Section
                    bulkAssignmentSection

                    Divider()
                        .padding(.horizontal, 16)

                    // Student Entries Section
                    studentEntriesSection

                    Divider()
                        .padding(.horizontal, 16)

                    // Group Observation Section
                    groupObservationSection
                }
                .padding(.vertical, 16)
            }
            .dismissKeyboardOnScroll()

            Divider()

            // Footer
            footer
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 700)
        .presentationSizingFitted()
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(!canDismiss)
        #endif
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 4) {
            Text("Presentation Complete")
                .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))

            Text(lessonName)
                .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                .foregroundStyle(.secondary)

            Text(Date(), style: .date)
                .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Presentation Status", systemImage: "flag.fill")
                .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            #if os(iOS)
            if horizontalSizeClass == .compact {
                VStack(spacing: 8) {
                    ForEach(PresentationStatus.allCases) { s in
                        statusButton(for: s)
                    }
                }
            } else {
                HStack(spacing: 12) {
                    ForEach(PresentationStatus.allCases) { s in
                        statusButton(for: s)
                    }
                }
            }
            #else
            HStack(spacing: 12) {
                ForEach(PresentationStatus.allCases) { s in
                    statusButton(for: s)
                }
            }
            #endif
        }
        .padding(.horizontal, 16)
    }

    private func statusButton(for s: PresentationStatus) -> some View {
        Button {
            viewModel.status = s
        } label: {
            HStack(spacing: 8) {
                Image(systemName: s.systemImage)
                Text(s.title)
            }
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .foregroundStyle(s.tint)
            .background(
                Capsule(style: .continuous)
                    .fill(s.tint.opacity(viewModel.status == s ? 0.20 : 0.10))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(s.tint.opacity(viewModel.status == s ? 0.5 : 0.25), lineWidth: viewModel.status == s ? 2 : 1)
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

            // Suggested follow-up work from lesson
            if !suggestedWorkItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Suggested by lesson:")
                        .font(.system(size: AppTheme.FontSize.captionSmall, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(suggestedWorkItems.enumerated()), id: \.offset) { index, suggestion in
                            Button {
                                viewModel.bulkAssignment = suggestion
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 11))
                                    Text(suggestion)
                                        .lineLimit(2)
                                    Spacer()
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.accentColor)
                                }
                                .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.accentColor.opacity(0.08))
                                )
                                .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.bottom, 4)
            }

            HStack(spacing: 8) {
                TextField("Set same assignment for all students...", text: $viewModel.bulkAssignment)
                    .textFieldStyle(.roundedBorder)

                Button("Apply") {
                    applyBulkAssignment()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.bulkAssignment.trimmed().isEmpty)
            }

            // Default schedule toggles
            HStack(spacing: 16) {
                Toggle("Check-in", isOn: $viewModel.defaultCheckInEnabled)
                    .toggleStyle(.switch)
                    .fixedSize()

                if viewModel.defaultCheckInEnabled {
                    DatePicker("", selection: $viewModel.defaultCheckInDate, displayedComponents: .date)
                        .labelsHidden()
                }

                Spacer()

                Toggle("Due", isOn: $viewModel.defaultDueEnabled)
                    .toggleStyle(.switch)
                    .fixedSize()

                if viewModel.defaultDueEnabled {
                    DatePicker("", selection: $viewModel.defaultDueDate, displayedComponents: .date)
                        .labelsHidden()
                }
            }
            .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
        }
        .padding(.horizontal, 16)
    }

    private func applyBulkAssignment() {
        let trimmed = viewModel.bulkAssignment.trimmed()
        guard !trimmed.isEmpty else { return }

        for studentID in viewModel.entries.keys {
            viewModel.entries[studentID]?.assignment = trimmed
            if viewModel.defaultCheckInEnabled {
                viewModel.entries[studentID]?.checkInDate = viewModel.defaultCheckInDate
            }
            if viewModel.defaultDueEnabled {
                viewModel.entries[studentID]?.dueDate = viewModel.defaultDueDate
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

                // Completion indicator
                let completed = viewModel.entries.values.filter { !$0.observation.isEmpty || !$0.assignment.isEmpty }.count
                Text("\(completed)/\(viewModel.entries.count)")
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
        let isExpanded = viewModel.expandedStudentIDs.contains(student.id)
        let entry = viewModel.entries[student.id]
        let hasContent = !(entry?.observation.isEmpty ?? true) || !(entry?.assignment.isEmpty ?? true)

        return VStack(spacing: 0) {
            // Header row (always visible)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        viewModel.expandedStudentIDs.remove(student.id)
                    } else {
                        viewModel.expandedStudentIDs.insert(student.id)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    // Student name
                    Text(StudentFormatter.displayName(for: student))
                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Spacer()

                    // Understanding level indicator
                    understandingIndicator(for: student.id)

                    // Status indicators
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
                VStack(spacing: 12) {
                    // Understanding level picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Understanding")
                            .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            ForEach(1...5, id: \.self) { level in
                                Button {
                                    viewModel.entries[student.id]?.understandingLevel = level
                                } label: {
                                    Circle()
                                        .fill(understandingColor(for: level).opacity(
                                            (viewModel.entries[student.id]?.understandingLevel ?? 3) >= level ? 1.0 : 0.2
                                        ))
                                        .frame(width: 24, height: 24)
                                }
                                .buttonStyle(.plain)
                            }

                            Spacer()

                            Text(understandingLabel(for: viewModel.entries[student.id]?.understandingLevel ?? 3))
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
                            get: { viewModel.entries[student.id]?.observation ?? "" },
                            set: { viewModel.entries[student.id]?.observation = $0 }
                        ), axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                    }

                    // Assignment
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Follow-up Work")
                            .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)

                        TextField("Assignment for this student...", text: Binding(
                            get: { viewModel.entries[student.id]?.assignment ?? "" },
                            set: { viewModel.entries[student.id]?.assignment = $0 }
                        ), axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                        
                        // Suggested work quick-pick buttons
                        if !suggestedWorkItems.isEmpty && (viewModel.entries[student.id]?.assignment ?? "").isEmpty {
                            HStack(spacing: 6) {
                                ForEach(Array(suggestedWorkItems.prefix(3).enumerated()), id: \.offset) { index, suggestion in
                                    suggestedWorkButton(for: suggestion, studentID: student.id)
                                }
                            }
                        }
                    }

                    // Schedule
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Check-in")
                                .font(.system(size: AppTheme.FontSize.captionSmall, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)

                            let hasCheckIn = viewModel.entries[student.id]?.checkInDate != nil
                            HStack(spacing: 4) {
                                Button {
                                    if hasCheckIn {
                                        viewModel.entries[student.id]?.checkInDate = nil
                                    } else {
                                        viewModel.entries[student.id]?.checkInDate = viewModel.defaultCheckInDate
                                    }
                                } label: {
                                    Image(systemName: hasCheckIn ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(hasCheckIn ? .blue : .secondary)
                                }
                                .buttonStyle(.plain)

                                if hasCheckIn {
                                    DatePicker("", selection: Binding(
                                        get: { viewModel.entries[student.id]?.checkInDate ?? viewModel.defaultCheckInDate },
                                        set: { viewModel.entries[student.id]?.checkInDate = $0 }
                                    ), displayedComponents: .date)
                                    .labelsHidden()
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Due Date")
                                .font(.system(size: AppTheme.FontSize.captionSmall, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)

                            let hasDue = viewModel.entries[student.id]?.dueDate != nil
                            HStack(spacing: 4) {
                                Button {
                                    if hasDue {
                                        viewModel.entries[student.id]?.dueDate = nil
                                    } else {
                                        viewModel.entries[student.id]?.dueDate = viewModel.defaultDueDate
                                    }
                                } label: {
                                    Image(systemName: hasDue ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(hasDue ? .blue : .secondary)
                                }
                                .buttonStyle(.plain)

                                if hasDue {
                                    DatePicker("", selection: Binding(
                                        get: { viewModel.entries[student.id]?.dueDate ?? viewModel.defaultDueDate },
                                        set: { viewModel.entries[student.id]?.dueDate = $0 }
                                    ), displayedComponents: .date)
                                    .labelsHidden()
                                }
                            }
                        }

                        Spacer()
                    }
                    
                    // Unlock Next Lesson
                    if let nextLesson = findNextLesson(for: student.id) {
                        Divider()
                            .padding(.vertical, 8)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Next Lesson")
                                    .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                                
                                Spacer()
                            }
                            
                            HStack(spacing: 8) {
                                Button {
                                    if viewModel.studentsToUnlock.contains(student.id) {
                                        viewModel.studentsToUnlock.remove(student.id)
                                    } else {
                                        viewModel.studentsToUnlock.insert(student.id)
                                    }
                                } label: {
                                    Image(systemName: viewModel.studentsToUnlock.contains(student.id) ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(viewModel.studentsToUnlock.contains(student.id) ? .green : .secondary)
                                }
                                .buttonStyle(.plain)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Unlock: \(nextLesson.name)")
                                        .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                                        .foregroundStyle(.primary)
                                    
                                    if viewModel.studentsToUnlock.contains(student.id) {
                                        Text("Will be unlocked when you click Done")
                                            .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                                            .foregroundStyle(.green)
                                    } else {
                                        Text("Lesson will remain blocked")
                                            .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                Spacer()
                            }
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                )
                .padding(.top, -4)
            }
        }
    }

    private func understandingIndicator(for studentID: UUID) -> some View {
        let level = viewModel.entries[studentID]?.understandingLevel ?? 3
        return HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Circle()
                    .fill(understandingColor(for: level).opacity(i <= level ? 1.0 : 0.2))
                    .frame(width: 8, height: 8)
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
    
    private func findNextLesson(for studentID: UUID) -> Lesson? {
        guard let currentLessonID = lessonID else { return nil }
        guard let currentLesson = lessons.first(where: { $0.id == currentLessonID }) else { return nil }
        
        // Use PlanNextLessonService to find the next lesson
        guard let nextLesson = PlanNextLessonService.findNextLesson(after: currentLesson, in: lessons) else {
            return nil
        }
        
        // Check if student already has this lesson manually unlocked
        let existingSLs = studentLessons.filter { sl in
            sl.resolvedLessonID == nextLesson.id &&
            sl.resolvedStudentIDs.contains(studentID)
        }
        
        // If any existing StudentLesson for this student+lesson combo is already manually unblocked, don't show
        if existingSLs.contains(where: { $0.manuallyUnblocked }) {
            return nil
        }
        
        return nextLesson
    }

    // MARK: - Group Observation Section

    private var groupObservationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Group Observation", systemImage: "text.bubble.fill")
                .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            TextField("Notes about the presentation overall...", text: $viewModel.groupObservation, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Cancel") {
                onCancel()
                dismiss()
            }

            Spacer()

            if !canDismiss {
                Text("Select a presented status to finish")
                    .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                    .foregroundStyle(.orange)
            }

            Button("Done") {
                // Apply default dates to entries that don't have them but have assignments
                var finalEntries = Array(viewModel.entries.values)
                for i in finalEntries.indices {
                    if !finalEntries[i].assignment.isEmpty {
                        if viewModel.defaultCheckInEnabled && finalEntries[i].checkInDate == nil {
                            finalEntries[i].checkInDate = viewModel.defaultCheckInDate
                        }
                        if viewModel.defaultDueEnabled && finalEntries[i].dueDate == nil {
                            finalEntries[i].dueDate = viewModel.defaultDueDate
                        }
                    }
                }
                
                // Unlock next lessons for selected students
                if let currentLessonID = lessonID, !viewModel.studentsToUnlock.isEmpty {
                    _ = UnlockNextLessonService.unlockNextLesson(
                        after: currentLessonID,
                        for: viewModel.studentsToUnlock,
                        modelContext: modelContext,
                        lessons: lessons,
                        studentLessons: studentLessons
                    )
                }

                onDone(viewModel.status, finalEntries, viewModel.groupObservation)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canDismiss)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
    
    // MARK: - Helper Views
    
    private func suggestedWorkButton(for suggestion: String, studentID: UUID) -> some View {
        Button {
            viewModel.entries[studentID]?.assignment = suggestion
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9))
                let truncated = suggestion.count > 20 ? String(suggestion.prefix(20)) + "..." : suggestion
                Text(truncated)
                    .lineLimit(1)
            }
            .font(.system(size: AppTheme.FontSize.captionSmall, weight: .medium, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(0.08))
            )
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    UnifiedPostPresentationSheet(
        students: [],
        lessonName: "Introduction to Fractions",
        onDone: { _, _, _ in },
        onCancel: {}
    )
}
#endif
