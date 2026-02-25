import OSLog
import SwiftUI
import SwiftData

/// Sheet for recording a practice session (solo or group) with students
struct PracticeSessionSheet: View {
    private static let logger = Logger.work

    let initialWorkItem: WorkModel
    var onSave: ((PracticeSession) -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @Query private var allStudents: [Student]
    @Query private var allWork: [WorkModel]
    @Query private var allLessonAssignments: [LessonAssignment]
    @Query private var allPracticeSessions: [PracticeSession]

    @State private var selectedDate: Date = Date()
    @State private var selectedStudentIDs: Set<UUID> = []
    @State private var selectedWorkItemIDs: Set<UUID> = []
    @State private var sharedNotes: String = ""
    @State private var duration: TimeInterval?
    @State private var hasDuration: Bool = false
    @State private var durationMinutes: Int = 30
    @State private var location: String = ""
    @State private var hasLocation: Bool = false
    @State private var searchText: String = ""

    // Session quality metrics
    @State private var practiceQuality: Int? = nil
    @State private var independenceLevel: Int? = nil

    // Individual notes per student (optional)
    @State private var individualNotes: [UUID: String] = [:]
    @State private var individualUnderstandingLevels: [UUID: Int] = [:]

    // Student selection sheet
    @State private var showStudentSelector: Bool = false
    
    // Presentation and lesson context
    @State private var relatedPresentation: Presentation? = nil
    @State private var relatedLesson: Lesson? = nil
    
    private var repository: PracticeSessionRepository {
        PracticeSessionRepository(modelContext: modelContext)
    }
    

    // Co-learner student IDs (students who had the lesson together)
    private var coLearnerIDs: Set<UUID> {
        StudentCategorizer.getCoLearnerIDs(for: initialWorkItem, allLessonAssignments: allLessonAssignments)
    }

    private var categorizer: StudentCategorizer {
        StudentCategorizer(
            initialWorkItem: initialWorkItem,
            allWork: allWork,
            allLessonAssignments: allLessonAssignments,
            allPracticeSessions: allPracticeSessions,
            coLearnerIDs: coLearnerIDs
        )
    }

    // All students ordered by category and search filter
    private var orderedStudents: [CategorizedStudent] {
        let categorized = allStudents
            .filter { !selectedStudentIDs.contains($0.id) }
            .map { categorizer.categorize($0) }
            .filter { categorized in
                // Apply search filter
                if searchText.isEmpty { return true }
                let displayName = StudentFormatter.displayName(for: categorized.student)
                return displayName.localizedCaseInsensitiveContains(searchText)
            }

        return StudentCategorizer.sort(categorized)
    }

    private var selectedStudents: [Student] {
        allStudents
            .filter { selectedStudentIDs.contains($0.id) }
            .sorted { $0.firstName < $1.firstName }
    }
    
    private var selectedWorkItems: [WorkModel] {
        allWork
            .filter { selectedWorkItemIDs.contains($0.id) }
            .sorted { $0.title < $1.title }
    }
    
    private var canSave: Bool {
        !selectedStudentIDs.isEmpty && !selectedWorkItemIDs.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Date selection
                        dateSection
                        
                        Divider()
                        
                        // Presentation & Lesson context
                        presentationContextSection
                        
                        Divider()
                        
                        // Currently practicing section with add button
                        currentlyPracticingSection
                        
                        Divider()
                        
                        // Shared notes
                        sharedNotesSection

                        Divider()

                        // Quality metrics
                        qualityMetricsSection

                        // Optional fields
                        optionalFieldsSection
                        
                        // Individual notes (expandable)
                        if !selectedStudents.isEmpty {
                            individualNotesSection
                        }
                    }
                    .padding(24)
                }
                .scrollDismissesKeyboard(.interactively)
                .sheet(isPresented: $showStudentSelector) {
                    studentSelectorSheet
                }
                
                Divider()
                
                // Bottom bar
                bottomBar
            }
            .navigationTitle("Practice Session")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                setupInitialState()
            }
        }
    }
    
    // MARK: - View Sections
    
    @ViewBuilder
    private var presentationContextSection: some View {
        if let lesson = relatedLesson {
            LessonContextCard(lesson: lesson, presentation: relatedPresentation)
        }
    }
    
    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PracticeSectionHeader(title: "Practice Date")

            DatePicker(
                "Date",
                selection: $selectedDate,
                displayedComponents: [.date]
            )
            .datePickerStyle(.compact)
            .labelsHidden()
        }
    }
    
    private var currentlyPracticingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                PracticeSectionHeader(title: "Students")

                Spacer()

                Button {
                    showStudentSelector = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Add Partners")
                            .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.accentColor))
                }
                .buttonStyle(.plain)
            }

            ForEach(selectedStudents) { student in
                SelectedStudentRow(
                    student: student,
                    workTitle: selectedWorkItems.first(where: { $0.studentID == student.id.uuidString })?.title,
                    showRemoveButton: selectedStudents.count > 1,
                    onRemove: {
                        selectedStudentIDs.remove(student.id)
                        if let work = selectedWorkItems.first(where: { $0.studentID == student.id.uuidString }) {
                            selectedWorkItemIDs.remove(work.id)
                        }
                    }
                )
            }
        }
    }
    
    private var studentSelectorSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                StudentSelectorSearchBar(searchText: $searchText)

                Divider()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if orderedStudents.isEmpty {
                            emptyPartnersMessage
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else {
                            studentSelectionList
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Add Practice Partners")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        showStudentSelector = false
                        searchText = "" // Clear search on dismiss
                    }
                }
            }
        }
    }

    private var emptyPartnersMessage: some View {
        Text(searchText.isEmpty ? "No other students have work for this lesson" : "No students match '\(searchText)'")
            .font(.system(size: AppTheme.FontSize.caption, weight: .regular, design: .rounded))
            .foregroundStyle(.secondary)
            .italic()
            .padding(.vertical, 8)
    }

    private var studentSelectionList: some View {
        ForEach(Array(groupedStudents.keys.sorted(by: { $0.rawValue < $1.rawValue })), id: \.rawValue) { category in
            if let students = groupedStudents[category] {
                StudentCategorySection(
                    category: category,
                    students: students,
                    onStudentTap: toggleStudent
                )
            }
        }
    }

    private var groupedStudents: [StudentCategory: [CategorizedStudent]] {
        Dictionary(grouping: orderedStudents, by: { $0.category })
    }
    
    private var sharedNotesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PracticeSectionHeader(title: "Session Notes")

            StyledNotesTextField(placeholder: "Add session notes...", text: $sharedNotes, lineLimit: 5...10)
        }
    }

    private var qualityMetricsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            PracticeSectionHeader(title: "Session Quality")

            RatingLevelSelector(
                label: "Engagement Level",
                selectedLevel: $practiceQuality,
                color: .blue,
                levelLabels: PracticeSessionLabels.qualityLabel
            )

            RatingLevelSelector(
                label: "Independence Level",
                selectedLevel: $independenceLevel,
                color: .green,
                levelLabels: PracticeSessionLabels.independenceLabel
            )
        }
    }


    private var optionalFieldsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            OptionalFieldToggle(title: "Track Duration", isEnabled: $hasDuration) {
                HStack {
                    Text("Duration (minutes)")
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Stepper("\(durationMinutes) min", value: $durationMinutes, in: 5...300, step: 5)
                        .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
                }
                .onChange(of: durationMinutes) { _, newValue in
                    duration = TimeInterval(newValue * 60)
                }
            }
            .onChange(of: hasDuration) { _, newValue in
                if !newValue {
                    duration = nil
                }
            }

            OptionalFieldToggle(title: "Add Location", isEnabled: $hasLocation) {
                TextField("Location (e.g., Small table, Outside)", text: $location)
                    .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.05))
                    )
            }
            .onChange(of: hasLocation) { _, newValue in
                if !newValue {
                    location = ""
                }
            }
        }
    }
    
    private var individualNotesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PracticeSectionHeader(title: "Individual Student Notes")

            ForEach(selectedStudents) { student in
                individualStudentCard(for: student)
            }
        }
    }

    @ViewBuilder
    private func individualStudentCard(for student: Student) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(StudentFormatter.displayName(for: student))
                .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))

            StudentUnderstandingSelector(level: Binding(
                get: { individualUnderstandingLevels[student.id] ?? 3 },
                set: { individualUnderstandingLevels[student.id] = $0 }
            ))

            VStack(alignment: .leading, spacing: 6) {
                Text("Notes")
                    .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                StyledNotesTextField(
                    placeholder: "Add notes for \(StudentFormatter.displayName(for: student))...",
                    text: Binding(
                        get: { individualNotes[student.id] ?? "" },
                        set: { individualNotes[student.id] = $0 }
                    )
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }


    private var bottomBar: some View {
        PracticeSessionBottomBar(
            canSave: canSave,
            onCancel: { dismiss() },
            onSave: { saveSession() }
        )
    }

    // MARK: - Helper Methods
    
    private func setupInitialState() {
        // Start with the initial work item's student and work
        if let studentID = UUID(uuidString: initialWorkItem.studentID) {
            selectedStudentIDs.insert(studentID)
        }
        selectedWorkItemIDs.insert(initialWorkItem.id)
        
        // Load presentation and lesson context
        relatedPresentation = initialWorkItem.fetchPresentation(from: modelContext)
        relatedLesson = initialWorkItem.fetchLesson(from: modelContext)
    }
    
    private func toggleStudent(_ student: Student) {
        if selectedStudentIDs.contains(student.id) {
            selectedStudentIDs.remove(student.id)
            // Remove their work item too
            if let work = findWorkForStudent(student) {
                selectedWorkItemIDs.remove(work.id)
            }
        } else {
            selectedStudentIDs.insert(student.id)
            // Add their work item
            if let work = findWorkForStudent(student) {
                selectedWorkItemIDs.insert(work.id)
            }
        }
    }
    
    private func findWorkForStudent(_ student: Student) -> WorkModel? {
        allWork.first { work in
            work.studentID == student.id.uuidString &&
            work.lessonID == initialWorkItem.lessonID &&
            work.status != .complete
        }
    }
    
    @MainActor
    private func saveSession() {
        // Create practice session
        let session = repository.create(
            date: selectedDate,
            duration: hasDuration ? duration : nil,
            studentIDs: Array(selectedStudentIDs),
            workItemIDs: Array(selectedWorkItemIDs),
            sharedNotes: sharedNotes,
            location: hasLocation ? location : nil
        )

        // Set quality metrics
        session.practiceQuality = practiceQuality
        session.independenceLevel = independenceLevel
        
        // Create individual notes with understanding levels if provided
        for studentID in selectedStudentIDs {
            let noteText = individualNotes[studentID] ?? ""
            let understandingLevel = individualUnderstandingLevels[studentID]

            // Only create note if there's text or understanding level
            guard !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || understandingLevel != nil else {
                continue
            }

            // Build note body with understanding level prefix if available
            var fullNoteBody = ""
            if let level = understandingLevel {
                fullNoteBody = "Understanding: \(PracticeSessionLabels.understandingLabel(for: level))"
                if !noteText.isEmpty {
                    fullNoteBody += "\n\n\(noteText)"
                }
            } else {
                fullNoteBody = noteText
            }

            let note = Note(
                body: fullNoteBody,
                scope: .student(studentID),
                category: .academic,
                practiceSession: session
            )
            modelContext.insert(note)
            note.syncStudentLinksIfNeeded(in: modelContext)
        }

        do {
            try modelContext.save()
        } catch {
            Self.logger.warning("Failed to save practice session: \(error)")
        }

        onSave?(session)
        dismiss()
    }
}

// MARK: - Preview

#Preview("Group Practice Sheet") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: AppSchema.schema, configurations: config)
    let context = container.mainContext
    
    // Create sample students
    let mary = Student(firstName: "Mary", lastName: "Smith", birthday: Date(), level: .lower)
    let danny = Student(firstName: "Danny", lastName: "Jones", birthday: Date(), level: .lower)
    let jane = Student(firstName: "Jane", lastName: "Doe", birthday: Date(), level: .lower)
    
    context.insert(mary)
    context.insert(danny)
    context.insert(jane)
    
    // Create sample lesson
    let lesson = Lesson()
    lesson.name = "Long Division"
    lesson.subject = "Math"
    lesson.group = "Operations"
    context.insert(lesson)
    
    // Create sample work items
    let work1 = WorkModel(
        title: "Practice Long Division",
        kind: .practiceLesson,
        studentID: danny.id.uuidString,
        lessonID: lesson.id.uuidString
    )
    let work2 = WorkModel(
        title: "Practice Long Division",
        kind: .practiceLesson,
        studentID: mary.id.uuidString,
        lessonID: lesson.id.uuidString
    )
    let work3 = WorkModel(
        title: "Practice Long Division",
        kind: .practiceLesson,
        studentID: jane.id.uuidString,
        lessonID: lesson.id.uuidString
    )
    
    context.insert(work1)
    context.insert(work2)
    context.insert(work3)
    
    return PracticeSessionSheet(initialWorkItem: work1)
        .modelContainer(container)
        .environment(SaveCoordinator())
}
