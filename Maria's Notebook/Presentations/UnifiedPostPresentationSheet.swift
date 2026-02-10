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
        students.sorted(by: StudentSortComparator.byFirstName)
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
        PresentationStudentRow(
            student: student,
            entry: Binding(
                get: { viewModel.entries[student.id] ?? StudentEntry(id: student.id, name: StudentFormatter.displayName(for: student)) },
                set: { viewModel.entries[student.id] = $0 }
            ),
            isExpanded: Binding(
                get: { viewModel.expandedStudentIDs.contains(student.id) },
                set: { if $0 { viewModel.expandedStudentIDs.insert(student.id) } else { viewModel.expandedStudentIDs.remove(student.id) } }
            ),
            suggestedWorkItems: suggestedWorkItems,
            nextLesson: findNextLesson(for: student.id),
            isUnlockSelected: Binding(
                get: { viewModel.studentsToUnlock.contains(student.id) },
                set: { if $0 { viewModel.studentsToUnlock.insert(student.id) } else { viewModel.studentsToUnlock.remove(student.id) } }
            ),
            defaultCheckInDate: viewModel.defaultCheckInDate,
            defaultDueDate: viewModel.defaultDueDate
        )
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
