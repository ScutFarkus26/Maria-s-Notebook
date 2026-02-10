import SwiftUI
import SwiftData

/// Sheet for recording a practice session (solo or group) with students
struct PracticeSessionSheet: View {
    let initialWorkItem: WorkModel
    var onSave: ((PracticeSession) -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @Query private var allStudents: [Student]
    @Query private var allWork: [WorkModel]
    @Query private var allStudentLessons: [StudentLesson]
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
    
    // MARK: - Student Ordering Categories

    enum StudentCategory: Int, Comparable {
        case withInitialStudent = 1    // Students who had lesson with initial student
        case practicing = 2             // Students practicing same lesson (active work)
        case recentlyPassed = 3        // Students who recently completed (within 30 days)
        case pastPractice = 4          // Students who practiced in the past
        case neverReceived = 5         // Students who never received the lesson

        static func < (lhs: StudentCategory, rhs: StudentCategory) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    private struct CategorizedStudent {
        let student: Student
        let category: StudentCategory
        let work: WorkModel?
        let daysSinceCompletion: Int?
        let lastPracticeDate: Date?
    }

    // Get the student lesson for the initial work item to find co-learners
    private var initialStudentLesson: StudentLesson? {
        guard let lessonUUID = UUID(uuidString: initialWorkItem.lessonID),
              let studentUUID = UUID(uuidString: initialWorkItem.studentID) else {
            return nil
        }

        return allStudentLessons.first { studentLesson in
            studentLesson.lessonIDUUID == lessonUUID &&
            studentLesson.studentIDs.contains(studentUUID.uuidString)
        }
    }

    // Co-learner student IDs (students who had the lesson together)
    private var coLearnerIDs: Set<UUID> {
        guard let studentLesson = initialStudentLesson else { return [] }
        return Set(studentLesson.studentIDs.compactMap { UUID(uuidString: $0) })
    }

    // Categorize a student based on their relationship to the lesson
    private func categorizeStudent(_ student: Student) -> CategorizedStudent {
        let lessonID = initialWorkItem.lessonID

        // Find work for this student and lesson
        let studentWork = allWork.filter {
            $0.studentID == student.id.uuidString &&
            $0.lessonID == lessonID &&
            $0.id != initialWorkItem.id
        }

        // Check if they're a co-learner
        if coLearnerIDs.contains(student.id) {
            let activeWork = studentWork.first { $0.status != .complete }
            return CategorizedStudent(
                student: student,
                category: .withInitialStudent,
                work: activeWork,
                daysSinceCompletion: nil,
                lastPracticeDate: nil
            )
        }

        // Check for active work (practicing)
        if let activeWork = studentWork.first(where: { $0.status != .complete }) {
            return CategorizedStudent(
                student: student,
                category: .practicing,
                work: activeWork,
                daysSinceCompletion: nil,
                lastPracticeDate: nil
            )
        }

        // Check for completed work (recently passed)
        if let completedWork = studentWork.first(where: { $0.status == .complete }) {
            let daysSince = completedWork.completedAt.map { Calendar.current.dateComponents([.day], from: $0, to: Date()).day ?? Int.max } ?? Int.max

            if daysSince <= 30 {
                return CategorizedStudent(
                    student: student,
                    category: .recentlyPassed,
                    work: completedWork,
                    daysSinceCompletion: daysSince,
                    lastPracticeDate: completedWork.completedAt
                )
            }
        }

        // Check for past practice sessions
        let practiceSessions = allPracticeSessions.filter { session in
            session.studentIDs.contains(student.id.uuidString) &&
            session.workItemIDs.contains { workID in
                if let work = allWork.first(where: { $0.id.uuidString == workID }) {
                    return work.lessonID == lessonID
                }
                return false
            }
        }.sorted { $0.date > $1.date }

        if let lastSession = practiceSessions.first {
            return CategorizedStudent(
                student: student,
                category: .pastPractice,
                work: nil,
                daysSinceCompletion: nil,
                lastPracticeDate: lastSession.date
            )
        }

        // Check if student has received the lesson at all
        let hasReceivedLesson = allStudentLessons.contains { studentLesson in
            guard let lessonUUID = UUID(uuidString: lessonID) else { return false }
            return studentLesson.lessonIDUUID == lessonUUID &&
                   studentLesson.studentIDs.contains(student.id.uuidString) &&
                   studentLesson.isPresented
        }

        if hasReceivedLesson {
            return CategorizedStudent(
                student: student,
                category: .pastPractice,
                work: nil,
                daysSinceCompletion: nil,
                lastPracticeDate: nil
            )
        }

        // Never received the lesson
        return CategorizedStudent(
            student: student,
            category: .neverReceived,
            work: nil,
            daysSinceCompletion: nil,
            lastPracticeDate: nil
        )
    }

    // All students ordered by category and search filter
    private var orderedStudents: [CategorizedStudent] {
        let categorized = allStudents
            .filter { !selectedStudentIDs.contains($0.id) }
            .map { categorizeStudent($0) }
            .filter { categorized in
                // Apply search filter
                if searchText.isEmpty { return true }
                let displayName = StudentFormatter.displayName(for: categorized.student)
                return displayName.localizedCaseInsensitiveContains(searchText)
            }

        return categorized.sorted { lhs, rhs in
            // First sort by category
            if lhs.category != rhs.category {
                return lhs.category < rhs.category
            }

            // Within category, sort by specific criteria
            switch lhs.category {
            case .withInitialStudent, .practicing:
                // Alphabetical
                return StudentFormatter.displayName(for: lhs.student) < StudentFormatter.displayName(for: rhs.student)

            case .recentlyPassed:
                // Most recently completed first
                if let lDays = lhs.daysSinceCompletion, let rDays = rhs.daysSinceCompletion {
                    return lDays < rDays
                }
                return false

            case .pastPractice:
                // Most recent practice first
                if let lDate = lhs.lastPracticeDate, let rDate = rhs.lastPracticeDate {
                    return lDate > rDate
                }
                return false

            case .neverReceived:
                // Alphabetical
                return StudentFormatter.displayName(for: lhs.student) < StudentFormatter.displayName(for: rhs.student)
            }
        }
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
            if let students = groupedStudents[category], !students.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    // Category header
                    Text(categoryLabel(for: category))
                        .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.top, category == .withInitialStudent ? 0 : 8)

                    // Students in this category
                    ForEach(students, id: \.student.id) { categorizedStudent in
                        studentSelectionRow(for: categorizedStudent)
                    }
                }
            }
        }
    }

    private var groupedStudents: [StudentCategory: [CategorizedStudent]] {
        Dictionary(grouping: orderedStudents, by: { $0.category })
    }

    private func categoryLabel(for category: StudentCategory) -> String {
        switch category {
        case .withInitialStudent:
            return "Learned Together"
        case .practicing:
            return "Currently Practicing"
        case .recentlyPassed:
            return "Recently Completed"
        case .pastPractice:
            return "Practiced Before"
        case .neverReceived:
            return "Never Received Lesson"
        }
    }
    
    private func studentSelectionRow(for categorizedStudent: CategorizedStudent) -> some View {
        Button {
            toggleStudent(categorizedStudent.student)
        } label: {
            HStack {
                Image(systemName: "square")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 20))

                VStack(alignment: .leading, spacing: 2) {
                    Text(StudentFormatter.displayName(for: categorizedStudent.student))
                        .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)

                    // Show work title or status info
                    if let work = categorizedStudent.work {
                        Text(work.title)
                            .font(.system(size: AppTheme.FontSize.caption, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else if let days = categorizedStudent.daysSinceCompletion {
                        Text("Completed \(days) day\(days == 1 ? "" : "s") ago")
                            .font(.system(size: AppTheme.FontSize.caption, weight: .regular, design: .rounded))
                            .foregroundStyle(.green)
                    } else if let date = categorizedStudent.lastPracticeDate {
                        Text("Last practiced \(date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.system(size: AppTheme.FontSize.caption, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 16))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
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
                levelLabels: qualityLabel
            )

            RatingLevelSelector(
                label: "Independence Level",
                selectedLevel: $independenceLevel,
                color: .green,
                levelLabels: independenceLabel
            )
        }
    }

    private func qualityLabel(for level: Int) -> String {
        switch level {
        case 1: return "Distracted"
        case 2: return "Minimal"
        case 3: return "Adequate"
        case 4: return "Good"
        case 5: return "Excellent"
        default: return ""
        }
    }

    private func independenceLabel(for level: Int) -> String {
        switch level {
        case 1: return "Constant Help"
        case 2: return "Frequent Guidance"
        case 3: return "Some Support"
        case 4: return "Mostly Independent"
        case 5: return "Fully Independent"
        default: return ""
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
                fullNoteBody = "Understanding: \(understandingLabel(for: level))"
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
        
        try? modelContext.save()
        
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
        .environmentObject(SaveCoordinator())
}
