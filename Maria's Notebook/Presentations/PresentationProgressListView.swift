import SwiftUI
import SwiftData

// MARK: - Extensions

extension LessonAssignment {
    /// Fetches the lesson for this presentation
    func fetchLesson(from context: ModelContext) -> Lesson? {
        guard !lessonID.isEmpty,
              let uuid = UUID(uuidString: lessonID) else { return nil }

        let descriptor = FetchDescriptor<Lesson>(
            predicate: #Predicate { $0.id == uuid }
        )

        return try? context.fetch(descriptor).first
    }
}

// MARK: - Main View

/// Shows all presentations with their follow-up work and practice outcomes
struct PresentationProgressListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LessonAssignment.scheduledForDay, order: .reverse) private var allPresentations: [LessonAssignment]
    
    @State private var viewModel = PresentationProgressViewModel()
    
    @State private var searchText = ""
    @State private var filterState: PresentationState?
    @State private var selectedPresentation: LessonAssignment?
    @State private var showingProgressDetail = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Presentation Progress")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Track each presentation and its follow-up work and practice outcomes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            
            Divider()
            
            // Filters
            HStack {
                Picker("Filter", selection: $filterState) {
                    Text("All").tag(nil as PresentationState?)
                    Text("Scheduled").tag(PresentationState.scheduled as PresentationState?)
                    Text("Presented").tag(PresentationState.presented as PresentationState?)
                    Text("Draft").tag(PresentationState.draft as PresentationState?)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 400)
                
                Spacer()
            }
            .padding()
            
            Divider()
            
            // List
            List(viewModel.presentations) { cached in
                PresentationProgressRow(cachedData: cached)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedPresentation = cached.presentation
                        showingProgressDetail = true
                    }
            }
            .searchable(text: $searchText, prompt: "Search lessons...")
            .overlay {
                if viewModel.presentations.isEmpty {
                    ContentUnavailableView(
                        "No Presentations",
                        systemImage: "person.3.sequence.fill",
                        description: Text("No presentations match your search")
                    )
                }
            }
        }
        .sheet(isPresented: $showingProgressDetail) {
            if let presentation = selectedPresentation {
                PresentationProgressDetailView(presentation: presentation) {
                    showingProgressDetail = false
                }
            }
        }
        .onAppear {
            viewModel.update(
                modelContext: modelContext,
                presentations: allPresentations,
                filterState: filterState,
                searchText: searchText
            )
        }
        .onChange(of: allPresentations) { _, newPresentations in
            viewModel.update(
                modelContext: modelContext,
                presentations: newPresentations,
                filterState: filterState,
                searchText: searchText
            )
        }
        .onChange(of: filterState) { _, _ in
            viewModel.update(
                modelContext: modelContext,
                presentations: allPresentations,
                filterState: filterState,
                searchText: searchText
            )
        }
        .onChange(of: searchText) { _, _ in
            viewModel.update(
                modelContext: modelContext,
                presentations: allPresentations,
                filterState: filterState,
                searchText: searchText
            )
        }
    }
}

// MARK: - Row View

/// Row showing presentation preview with stats
struct PresentationProgressRow: View {
    let cachedData: PresentationWithCachedData

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Lesson title and date
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(cachedData.lesson.name)
                        .font(.headline)

                    if cachedData.presentation.scheduledForDay != Date.distantPast {
                        Text(cachedData.presentation.scheduledForDay.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // State badge using component
                PresentationStateBadge(state: cachedData.presentation.state)
            }

            // Students
            if !cachedData.presentation.studentIDs.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(cachedData.presentation.studentIDs.count) students")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Stats badges using component
            HStack(spacing: 12) {
                PresentationStatBadge(
                    icon: "doc.text.fill",
                    value: "\(cachedData.workStats.total)",
                    label: "Work Items",
                    color: .blue
                )

                if cachedData.workStats.total > 0 {
                    PresentationStatBadge(
                        icon: "checkmark.circle.fill",
                        value: "\(cachedData.workStats.completed)",
                        label: "Completed",
                        color: .green
                    )
                }

                if cachedData.practiceCount > 0 {
                    PresentationStatBadge(
                        icon: "figure.run",
                        value: "\(cachedData.practiceCount)",
                        label: "Practice",
                        color: .orange
                    )
                }
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 8)
    }
}

/// Detailed view for a single presentation's progress
struct PresentationProgressDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let presentation: LessonAssignment
    let onDone: () -> Void
    
    @State private var lesson: Lesson?
    @State private var students: [Student] = []
    @State private var workItems: [WorkModel] = []
    @State private var practiceSessions: [PracticeSession] = []
    @State private var showingEditSheet = false
    
    // Filtering and grouping
    @State private var filterStatus: WorkStatus?
    @State private var showCompletedOnly = false
    @State private var showIncompleteOnly = false
    @State private var groupByStatus = false
    
    // Student progress data
    @State private var studentProgress: [UUID: StudentWorkProgress] = [:]
    
    private var filteredStudents: [Student] {
        var result = students
        
        // Filter by completion status
        if showCompletedOnly {
            result = result.filter { student in
                let progress = studentProgress[student.id]
                return progress?.isAllCompleted ?? false
            }
        } else if showIncompleteOnly {
            result = result.filter { student in
                let progress = studentProgress[student.id]
                return !(progress?.isAllCompleted ?? true)
            }
        }
        
        return result
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header section
                    VStack(alignment: .leading, spacing: 12) {
                        Text(lesson?.name ?? "Unknown Lesson")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        HStack {
                            if presentation.scheduledForDay != Date.distantPast {
                                Label(
                                    presentation.scheduledForDay.formatted(date: .abbreviated, time: .omitted),
                                    systemImage: "calendar"
                                )
                            }
                            
                            Text("•")
                                .foregroundStyle(.secondary)
                            
                            Text(presentation.state.rawValue.capitalized)
                                .foregroundStyle(stateBadgeColor)
                                .fontWeight(.medium)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Overall stats
                    if !students.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Overview", systemImage: "chart.bar.fill")
                                .font(.headline)

                            HStack(spacing: 16) {
                                PresentationStatBadge(
                                    icon: "person.2.fill",
                                    value: "\(students.count)",
                                    label: "Students",
                                    color: .blue
                                )

                                PresentationStatBadge(
                                    icon: "doc.text.fill",
                                    value: "\(workItems.count)",
                                    label: "Work Items",
                                    color: .purple
                                )

                                if !workItems.isEmpty {
                                    let completed = workItems.filter { $0.status == .complete }.count
                                    PresentationStatBadge(
                                        icon: "checkmark.circle.fill",
                                        value: "\(completed)/\(workItems.count)",
                                        label: "Completed",
                                        color: .green
                                    )
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Filters
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Filter Students", systemImage: "line.3.horizontal.decrease.circle")
                            .font(.headline)

                        HStack(spacing: 12) {
                            FilterToggleButton(
                                icon: "checkmark.circle.fill",
                                title: "Completed Only",
                                color: .green,
                                isSelected: showCompletedOnly
                            ) {
                                showCompletedOnly.toggle()
                                if showCompletedOnly {
                                    showIncompleteOnly = false
                                }
                            }

                            FilterToggleButton(
                                icon: "checkmark.circle.fill",
                                title: "Incomplete Only",
                                color: .orange,
                                isSelected: showIncompleteOnly
                            ) {
                                showIncompleteOnly.toggle()
                                if showIncompleteOnly {
                                    showCompletedOnly = false
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Student progress section
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Student Progress", systemImage: "person.2.fill")
                            .font(.headline)
                        
                        if filteredStudents.isEmpty {
                            Text(showCompletedOnly || showIncompleteOnly ? "No students match the filter" : "No students assigned")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(filteredStudents) { student in
                                StudentProgressCard(
                                    student: student,
                                    progress: studentProgress[student.id] ?? StudentWorkProgress(),
                                    modelContext: modelContext
                                )
                            }
                        }
                    }
                    
                    Divider()
                    
                    // All work items section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("All Follow-Up Work", systemImage: "doc.text.fill")
                                .font(.headline)
                            
                            Spacer()
                            
                            if !workItems.isEmpty {
                                let completed = workItems.filter { $0.status == .complete }.count
                                Text("\(completed)/\(workItems.count)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        if workItems.isEmpty {
                            Text("No work items created yet")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(workItems) { work in
                                WorkProgressRow(work: work)
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Practice sessions section
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Practice Sessions", systemImage: "figure.run")
                            .font(.headline)
                        
                        if practiceSessions.isEmpty {
                            Text("No practice sessions yet")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(practiceSessions) { session in
                                PracticeSessionRow(session: session)
                            }
                        }
                    }
                    
                    // Presentation flags
                    if presentation.needsPractice || presentation.needsAnotherPresentation || !presentation.followUpWork.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            Label("Flags", systemImage: "flag.fill")
                                .font(.headline)

                            VStack(alignment: .leading, spacing: 8) {
                                if presentation.needsPractice {
                                    PresentationFlagBadge(text: "Needs Practice", color: .orange)
                                }
                                if presentation.needsAnotherPresentation {
                                    PresentationFlagBadge(text: "Needs Another Presentation", color: .red)
                                }
                                if !presentation.followUpWork.isEmpty {
                                    PresentationFlagBadge(text: "Follow-Up Work", color: .blue)
                                }
                            }
                        }
                    }
                    
                    // Notes
                    if !presentation.notes.isEmpty {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Notes", systemImage: "note.text")
                                .font(.headline)
                            
                            Text(presentation.notes)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Presentation Progress")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onDone()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Edit") {
                        showingEditSheet = true
                    }
                    .disabled(students.isEmpty || lesson == nil || !workItems.isEmpty)
                }
            }
            .sheet(isPresented: $showingEditSheet) {
                editPresentationSheet
            }
            .task {
                loadData()
            }
        }
    }

    private var editPresentationSheet: some View {
        // Get the lessonID from the presentation
        guard let lessonIDUUID = presentation.lessonIDUUID,
              !students.isEmpty else {
            return AnyView(EmptyView())
        }
        
        return AnyView(
            UnifiedPresentationWorkflowSheet(
                students: students,
                lessonName: lesson?.name ?? "Unknown Lesson",
                lessonID: lessonIDUUID,
                onComplete: {
                    // Work items are created by the workflow sheet
                    showingEditSheet = false
                    loadData()
                },
                onCancel: {
                    showingEditSheet = false
                }
            )
        )
    }

    private var stateBadgeColor: Color {
        switch presentation.state {
        case .draft: return .gray
        case .scheduled: return .blue
        case .presented: return .green
        }
    }

    @MainActor
    private func loadData() {
        lesson = presentation.fetchLesson(from: modelContext)
        students = presentation.fetchStudents(from: modelContext)
        workItems = presentation.fetchRelatedWork(from: modelContext)
        practiceSessions = presentation.fetchRelatedPracticeSessions(from: modelContext)
        
        // Calculate per-student progress
        calculateStudentProgress()
    }
    
    @MainActor
    private func calculateStudentProgress() {
        var progress: [UUID: StudentWorkProgress] = [:]
        
        for student in students {
            let studentIDString = student.id.uuidString
            let studentWork = workItems.filter { $0.studentID == studentIDString }
            
            let completed = studentWork.filter { $0.status == .complete }
            let active = studentWork.filter { $0.status == .active }
            let review = studentWork.filter { $0.status == .review }
            
            // Get work with outcomes
            let mastered = studentWork.filter { $0.completionOutcome == .mastered }
            let needsPractice = studentWork.filter { $0.completionOutcome == .needsMorePractice }
            let needsReview = studentWork.filter { $0.completionOutcome == .needsReview }
            
            // Get check-ins
            var totalCheckIns = 0
            for work in studentWork {
                if let checkIns = work.checkIns {
                    totalCheckIns += checkIns.count
                }
            }
            
            progress[student.id] = StudentWorkProgress(
                totalWork: studentWork.count,
                completedWork: completed.count,
                activeWork: active.count,
                reviewWork: review.count,
                masteredWork: mastered.count,
                needsPracticeWork: needsPractice.count,
                needsReviewWork: needsReview.count,
                checkInsCount: totalCheckIns,
                workItems: studentWork
            )
        }
        
        studentProgress = progress
    }
}
