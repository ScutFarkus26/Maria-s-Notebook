import OSLog
import SwiftUI
import SwiftData

/// Sheet for recording a practice session (solo or group) with students
struct PracticeSessionSheet: View {
    private static let logger = Logger.work

    let initialWorkItem: WorkModel
    var onSave: ((PracticeSession) -> Void)?
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @Query private var allStudentsRaw: [Student]
    private var allStudents: [Student] { allStudentsRaw.filter(\.isEnrolled) }
    @Query private var allWork: [WorkModel]
    @Query private var allLessonAssignments: [LessonAssignment]
    @Query private var allPracticeSessions: [PracticeSession]

    @State var selectedDate: Date = Date()
    @State var selectedStudentIDs: Set<UUID> = []
    @State var selectedWorkItemIDs: Set<UUID> = []
    @State var sharedNotes: String = ""
    @State var duration: TimeInterval?
    @State var hasDuration: Bool = false
    @State var durationMinutes: Int = 30
    @State var location: String = ""
    @State var hasLocation: Bool = false
    @State var searchText: String = ""

    // Session quality metrics
    @State var practiceQuality: Int?
    @State var independenceLevel: Int?

    // Individual notes per student (optional)
    @State var individualNotes: [UUID: String] = [:]
    @State var individualUnderstandingLevels: [UUID: Int] = [:]

    // Student selection sheet
    @State var showStudentSelector: Bool = false
    
    // Presentation and lesson context
    @State private var relatedPresentation: Presentation?
    @State private var relatedLesson: Lesson?
    
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
    var orderedStudents: [CategorizedStudent] {
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

    var selectedStudents: [Student] {
        allStudents
            .filter { selectedStudentIDs.contains($0.id) }
            .sorted { $0.firstName < $1.firstName }
    }
    
    var selectedWorkItems: [WorkModel] {
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
            .inlineNavigationTitle()
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
                            .font(AppTheme.ScaledFont.captionSemibold)
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
    
    var sharedNotesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PracticeSectionHeader(title: "Session Notes")

            StyledNotesTextField(placeholder: "Add session notes...", text: $sharedNotes, lineLimit: 5...10)
        }
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
    
    func toggleStudent(_ student: Student) {
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
            guard !noteText.trimmed().isEmpty || understandingLevel != nil else {
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
                tags: [TagHelper.tagFromNoteCategory("academic")],
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
    let container: ModelContainer
    do {
        container = try ModelContainer(for: AppSchema.schema, configurations: config)
    } catch {
        fatalError("Preview ModelContainer failed: \(error)")
    }
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
