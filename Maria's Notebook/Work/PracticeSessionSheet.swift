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
    @State private var showIndividualNotes: Bool = false
    
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
        }.sorted { ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast) }

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

    // Legacy property for backward compatibility
    private var suggestedStudents: [Student] {
        orderedStudents.map { $0.student }
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
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "book.closed.fill")
                        .foregroundStyle(.indigo)
                        .font(.system(size: 16))
                    Text("Lesson Context")
                        .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    // Lesson info
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(lesson.name)
                                .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                            
                            if !lesson.subject.isEmpty || !lesson.group.isEmpty {
                                HStack(spacing: 6) {
                                    if !lesson.subject.isEmpty {
                                        Text(lesson.subject)
                                            .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    if !lesson.subject.isEmpty && !lesson.group.isEmpty {
                                        Text("•")
                                            .foregroundStyle(.tertiary)
                                    }
                                    
                                    if !lesson.group.isEmpty {
                                        Text(lesson.group)
                                            .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.indigo.opacity(0.08))
                    )
                    
                    // Presentation info if available
                    if let presentation = relatedPresentation {
                        HStack(spacing: 8) {
                            Image(systemName: presentation.isPresented ? "calendar.badge.checkmark" : "calendar")
                                .font(.system(size: 14))
                                .foregroundStyle(.indigo)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(presentation.isPresented ? "Presented" : "Scheduled")
                                    .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                                
                                if let date = presentation.presentedAt ?? presentation.scheduledFor {
                                    Text(date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            Spacer()
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.indigo.opacity(0.05))
                        )
                    }
                }
            }
        }
    }
    
    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Practice Date")
                .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            
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
                Text("Students")
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                
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
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 16))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(StudentFormatter.displayName(for: student))
                            .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
                        
                        if let work = selectedWorkItems.first(where: { $0.studentID == student.id.uuidString }) {
                            Text(work.title)
                                .font(.system(size: AppTheme.FontSize.caption, weight: .regular, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    if selectedStudents.count > 1 {
                        Button {
                            selectedStudentIDs.remove(student.id)
                            if let work = selectedWorkItems.first(where: { $0.studentID == student.id.uuidString }) {
                                selectedWorkItemIDs.remove(work.id)
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.green.opacity(0.1))
                )
            }
        }
    }
    
    private var studentSelectorSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))

                    TextField("Search students...", text: $searchText)
                        .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                        .textFieldStyle(.plain)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(Color.primary.opacity(0.05))
                
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
        ForEach(Array(groupedStudents.keys.sorted(by: <)), id: \.rawValue) { category in
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
            Text("Session Notes")
                .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            
            TextField("Add session notes...", text: $sharedNotes, axis: .vertical)
                .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                .lineLimit(5...10)
                .textFieldStyle(.plain)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                )
        }
    }

    private var qualityMetricsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Session Quality")
                .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            // Practice Quality
            VStack(alignment: .leading, spacing: 8) {
                Text("Engagement Level")
                    .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    ForEach(1...5, id: \.self) { level in
                        Button {
                            practiceQuality = (practiceQuality == level) ? nil : level
                        } label: {
                            Circle()
                                .fill(Color.blue.opacity(practiceQuality == level ? 1.0 : 0.2))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Text("\(level)")
                                        .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                                        .foregroundStyle(practiceQuality == level ? .white : .blue)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    if let quality = practiceQuality {
                        Text(qualityLabel(for: quality))
                            .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Independence Level
            VStack(alignment: .leading, spacing: 8) {
                Text("Independence Level")
                    .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    ForEach(1...5, id: \.self) { level in
                        Button {
                            independenceLevel = (independenceLevel == level) ? nil : level
                        } label: {
                            Circle()
                                .fill(Color.green.opacity(independenceLevel == level ? 1.0 : 0.2))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Text("\(level)")
                                        .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                                        .foregroundStyle(independenceLevel == level ? .white : .green)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    if let independence = independenceLevel {
                        Text(independenceLabel(for: independence))
                            .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
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
            // Duration toggle
            Toggle(isOn: $hasDuration) {
                Text("Track Duration")
                    .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
            }
            .onChange(of: hasDuration) { _, newValue in
                if !newValue {
                    duration = nil
                }
            }
            
            if hasDuration {
                HStack {
                    Text("Duration (minutes)")
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Stepper("\(durationMinutes) min", value: $durationMinutes, in: 5...300, step: 5)
                        .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
                }
                .padding(.leading, 24)
                .onChange(of: durationMinutes) { _, newValue in
                    duration = TimeInterval(newValue * 60)
                }
            }
            
            // Location toggle
            Toggle(isOn: $hasLocation) {
                Text("Add Location")
                    .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
            }
            .onChange(of: hasLocation) { _, newValue in
                if !newValue {
                    location = ""
                }
            }
            
            if hasLocation {
                TextField("Location (e.g., Small table, Outside)", text: $location)
                    .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .padding(.leading, 24)
            }
        }
    }
    
    private var individualNotesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Individual Student Notes")
                .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            ForEach(selectedStudents) { student in
                individualStudentCard(for: student)
            }
        }
    }

    @ViewBuilder
    private func individualStudentCard(for student: Student) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Student name
            Text(StudentFormatter.displayName(for: student))
                .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))

            // Understanding level picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Understanding")
                    .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { level in
                        Button {
                            individualUnderstandingLevels[student.id] = level
                        } label: {
                            Circle()
                                .fill(understandingColor(for: level).opacity(
                                    (individualUnderstandingLevels[student.id] ?? 3) >= level ? 1.0 : 0.2
                                ))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Text(understandingLabel(for: individualUnderstandingLevels[student.id] ?? 3))
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            // Notes
            VStack(alignment: .leading, spacing: 6) {
                Text("Notes")
                    .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                TextField("Add notes for \(StudentFormatter.displayName(for: student))...", text: Binding(
                    get: { individualNotes[student.id] ?? "" },
                    set: { individualNotes[student.id] = $0 }
                ), axis: .vertical)
                .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                .lineLimit(3...8)
                .textFieldStyle(.plain)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
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
    
    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.primary.opacity(0.05))
                    )
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                saveSession()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Save Session")
                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(canSave ? Color.accentColor : Color.gray)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
        }
        .padding(16)
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
