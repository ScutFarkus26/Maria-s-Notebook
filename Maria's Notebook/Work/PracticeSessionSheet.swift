import OSLog
import SwiftUI
import CoreData

/// Sheet for recording a practice session (solo or group) with students
struct PracticeSessionSheet: View {
    private static let logger = Logger.work

    let initialWorkItem: WorkModel
    var onSave: ((PracticeSession) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDStudent.firstName, ascending: true)])
    private var allStudentsRaw: FetchedResults<CDStudent>
    private var allStudents: [Student] { Array(allStudentsRaw).filter(\.isEnrolled) }
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDWorkModel.createdAt, ascending: false)])
    private var allWork: FetchedResults<CDWorkModel>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLessonAssignment.presentedAt, ascending: false)])
    private var allLessonAssignments: FetchedResults<CDLessonAssignment>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDPracticeSession.date, ascending: false)])
    private var allPracticeSessions: FetchedResults<CDPracticeSession>

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
        PracticeSessionRepository(context: viewContext) // swiftlint:disable:this deprecated
    }
    
    // Co-learner student IDs (students who had the lesson together)
    private var coLearnerIDs: Set<UUID> {
        StudentCategorizer.getCoLearnerIDs(for: initialWorkItem, allLessonAssignments: allLessonAssignments)
    }

    private var categorizer: StudentCategorizer {
        StudentCategorizer(
            initialWorkItem: initialWorkItem,
            allWork: Array(allWork),
            allLessonAssignments: Array(allLessonAssignments),
            allPracticeSessions: Array(allPracticeSessions),
            coLearnerIDs: coLearnerIDs
        )
    }

    // All students ordered by category and search filter
    var orderedStudents: [CategorizedStudent] {
        let categorized = allStudents
            .filter { guard let id = $0.id else { return false }; return !selectedStudentIDs.contains(id) }
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
            .filter { guard let id = $0.id else { return false }; return selectedStudentIDs.contains(id) }
            .sorted { $0.firstName < $1.firstName }
    }

    var selectedWorkItems: [WorkModel] {
        Array(allWork)
            .filter { guard let id = $0.id else { return false }; return selectedWorkItemIDs.contains(id) }
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
                    workTitle: selectedWorkItems.first(where: { $0.studentID == student.id?.uuidString ?? "" })?.title,
                    showRemoveButton: selectedStudents.count > 1,
                    onRemove: {
                        if let sid = student.id { selectedStudentIDs.remove(sid) }
                        if let work = selectedWorkItems.first(where: { $0.studentID == (student.id?.uuidString ?? "") }) {
                            if let wid = work.id { selectedWorkItemIDs.remove(wid) }
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
        if let workID = initialWorkItem.id {
            selectedWorkItemIDs.insert(workID)
        }
        
        // Load presentation and lesson context
        relatedPresentation = initialWorkItem.fetchPresentation(from: viewContext)
        relatedLesson = initialWorkItem.fetchLesson(from: viewContext)
    }
    
    func toggleStudent(_ student: Student) {
        guard let studentID = student.id else { return }
        if selectedStudentIDs.contains(studentID) {
            selectedStudentIDs.remove(studentID)
            // Remove their work item too
            if let work = findWorkForStudent(student), let wid = work.id {
                selectedWorkItemIDs.remove(wid)
            }
        } else {
            selectedStudentIDs.insert(studentID)
            // Add their work item
            if let work = findWorkForStudent(student), let wid = work.id {
                selectedWorkItemIDs.insert(wid)
            }
        }
    }
    
    private func findWorkForStudent(_ student: Student) -> WorkModel? {
        let studentIDString = student.id?.uuidString ?? ""
        return allWork.first { work in
            work.studentID == studentIDString &&
            work.lessonID == initialWorkItem.lessonID &&
            work.status != .complete
        }
    }
    
    @MainActor
    private func saveSession() {
        // Create practice session
        let session = PracticeSession(context: viewContext)
        session.date = selectedDate
        session.durationInterval = hasDuration ? duration : nil
        session.studentIDsArray = Array(selectedStudentIDs).map(\.uuidString)
        session.workItemIDsArray = Array(selectedWorkItemIDs).map(\.uuidString)
        session.sharedNotes = sharedNotes
        session.location = hasLocation ? location : nil

        // Set quality metrics
        session.practiceQualityValue = practiceQuality
        session.independenceLevelValue = independenceLevel
        
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

            let note = Note(context: viewContext)
            note.body = fullNoteBody
            note.scope = .student(studentID)
            note.tagsArray = [TagHelper.tagFromNoteCategory("academic")]
            note.practiceSession = session
            // Student links managed by Core Data relationships
        }

        do {
            try viewContext.save()
        } catch {
            Self.logger.warning("Failed to save practice session: \(error)")
        }

        onSave?(session)
        dismiss()
    }
}

// MARK: - Preview

#Preview("Group Practice Sheet") {
    let stack = CoreDataStack.preview
    let ctx = stack.viewContext

    let mary = Student(context: ctx)
    mary.firstName = "Mary"; mary.lastName = "Smith"; mary.birthday = Date(); mary.level = .lower
    let danny = Student(context: ctx)
    danny.firstName = "Danny"; danny.lastName = "Jones"; danny.birthday = Date(); danny.level = .lower
    let jane = Student(context: ctx)
    jane.firstName = "Jane"; jane.lastName = "Doe"; jane.birthday = Date(); jane.level = .lower

    let lesson = Lesson(context: ctx)
    lesson.name = "Long Division"; lesson.subject = "Math"; lesson.group = "Operations"

    let work1 = WorkModel(context: ctx)
    work1.title = "Practice Long Division"; work1.kind = .practiceLesson
    work1.studentID = danny.id?.uuidString ?? ""; work1.lessonID = lesson.id?.uuidString ?? ""
    let work2 = WorkModel(context: ctx)
    work2.title = "Practice Long Division"; work2.kind = .practiceLesson
    work2.studentID = mary.id?.uuidString ?? ""; work2.lessonID = lesson.id?.uuidString ?? ""
    let work3 = WorkModel(context: ctx)
    work3.title = "Practice Long Division"; work3.kind = .practiceLesson
    work3.studentID = jane.id?.uuidString ?? ""; work3.lessonID = lesson.id?.uuidString ?? ""

    return PracticeSessionSheet(initialWorkItem: work1)
        .previewEnvironment(using: stack)
}
