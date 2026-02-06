import SwiftUI
import SwiftData

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

/// Shows all presentations with their follow-up work and practice outcomes
struct PresentationProgressListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LessonAssignment.scheduledForDay, order: .reverse) private var allPresentations: [LessonAssignment]
    
    @StateObject private var viewModel = PresentationProgressViewModel()
    
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
                        systemImage: "presentation.person.line",
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
                
                // State badge
                Text(cachedData.presentation.state.rawValue.capitalized)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(stateBadgeColor.opacity(0.2))
                    .foregroundStyle(stateBadgeColor)
                    .clipShape(Capsule())
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
            
            // Stats badges
            HStack(spacing: 12) {
                StatBadge(
                    icon: "doc.text.fill",
                    value: "\(cachedData.workStats.total)",
                    label: "Work Items",
                    color: .blue
                )
                
                if cachedData.workStats.total > 0 {
                    StatBadge(
                        icon: "checkmark.circle.fill",
                        value: "\(cachedData.workStats.completed)",
                        label: "Completed",
                        color: .green
                    )
                }
                
                if cachedData.practiceCount > 0 {
                    StatBadge(
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
    
    private var stateBadgeColor: Color {
        switch cachedData.presentation.state {
        case .presented: return .green
        case .scheduled: return .blue
        case .draft: return .gray
        }
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
                                StatBadge(
                                    icon: "person.2.fill",
                                    value: "\(students.count)",
                                    label: "Students",
                                    color: .blue
                                )
                                
                                StatBadge(
                                    icon: "doc.text.fill",
                                    value: "\(workItems.count)",
                                    label: "Work Items",
                                    color: .purple
                                )
                                
                                if !workItems.isEmpty {
                                    let completed = workItems.filter { $0.status == .complete }.count
                                    StatBadge(
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
                            Button {
                                showCompletedOnly.toggle()
                                if showCompletedOnly {
                                    showIncompleteOnly = false
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: showCompletedOnly ? "checkmark.circle.fill" : "circle")
                                    Text("Completed Only")
                                }
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(showCompletedOnly ? Color.green.opacity(0.2) : Color.gray.opacity(0.1))
                                .foregroundStyle(showCompletedOnly ? .green : .primary)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            
                            Button {
                                showIncompleteOnly.toggle()
                                if showIncompleteOnly {
                                    showCompletedOnly = false
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: showIncompleteOnly ? "checkmark.circle.fill" : "circle")
                                    Text("Incomplete Only")
                                }
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(showIncompleteOnly ? Color.orange.opacity(0.2) : Color.gray.opacity(0.1))
                                .foregroundStyle(showIncompleteOnly ? .orange : .primary)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
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
                                    FlagBadge(text: "Needs Practice", color: .orange)
                                }
                                if presentation.needsAnotherPresentation {
                                    FlagBadge(text: "Needs Another Presentation", color: .red)
                                }
                                if !presentation.followUpWork.isEmpty {
                                    FlagBadge(text: "Follow-Up Work", color: .blue)
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
                    .disabled(students.isEmpty || lesson == nil)
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
    
    private var stateBadgeColor: Color {
        switch presentation.state {
        case .presented: return .green
        case .scheduled: return .blue
        case .draft: return .gray
        }
    }
    
    private var editPresentationSheet: some View {
        let initialStatus: UnifiedPostPresentationSheet.PresentationStatus = {
            if presentation.state == .presented {
                return .justPresented
            } else {
                return .justPresented
            }
        }()
        
        return UnifiedPostPresentationSheet(
            students: students,
            lessonName: lesson?.name ?? "Unknown Lesson",
            initialStatus: initialStatus,
            onDone: { status, studentEntries, groupObservation in
                updatePresentation(status: status, entries: studentEntries, groupObservation: groupObservation)
                showingEditSheet = false
            },
            onCancel: {
                showingEditSheet = false
            }
        )
    }
    
    @MainActor
    private func updatePresentation(status: UnifiedPostPresentationSheet.PresentationStatus, entries: [UnifiedPostPresentationSheet.StudentEntry], groupObservation: String) {
        // Update presentation state
        switch status {
        case .justPresented:
            presentation.state = .presented
            presentation.presentedAt = Date()
            presentation.needsAnotherPresentation = false
        case .previouslyPresented:
            presentation.state = .presented
            presentation.needsAnotherPresentation = false
        case .needsAnother:
            presentation.state = .scheduled
            presentation.needsAnotherPresentation = true
        }
        
        // Update notes with group observation
        if !groupObservation.isEmpty {
            if presentation.notes.isEmpty {
                presentation.notes = groupObservation
            } else {
                presentation.notes += "\n\n" + groupObservation
            }
        }
        
        // Save changes
        try? modelContext.save()
        
        // Reload data to reflect changes
        loadData()
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

// MARK: - Supporting Views

struct WorkProgressRow: View {
    @Environment(\.modelContext) private var modelContext
    let work: WorkModel
    
    @State private var practiceCount: Int = 0
    @State private var student: Student?
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(work.title)
                    .font(.subheadline)
                
                if let student = student {
                    Text(student.fullName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                if practiceCount > 0 {
                    Label("\(practiceCount)", systemImage: "figure.run")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                
                Image(systemName: work.status == .complete ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(work.status == .complete ? .green : .secondary)
            }
        }
        .padding(.vertical, 8)
        .task {
            student = work.fetchStudent(from: modelContext)
            practiceCount = work.fetchPracticeSessions(from: modelContext).count
        }
    }
}

struct PracticeSessionRow: View {
    let session: PracticeSession
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Practice Session")
                    .font(.subheadline)
                
                Text(session.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if let duration = session.duration {
                let minutes = Int(duration / 60)
                Text("\(minutes) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

struct FlagBadge: View {
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "flag.fill")
            Text(text)
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.2))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }
}

struct StatBadge: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(label)
                    .font(.caption2)
            }
        }
        .foregroundStyle(color)
    }
}

// MARK: - Student Progress Tracking

/// Tracks a single student's progress on work from a presentation
struct StudentWorkProgress {
    var totalWork: Int = 0
    var completedWork: Int = 0
    var activeWork: Int = 0
    var reviewWork: Int = 0
    var masteredWork: Int = 0
    var needsPracticeWork: Int = 0
    var needsReviewWork: Int = 0
    var checkInsCount: Int = 0
    var workItems: [WorkModel] = []
    
    var isAllCompleted: Bool {
        totalWork > 0 && completedWork == totalWork
    }
    
    var hasWork: Bool {
        totalWork > 0
    }
    
    var completionPercentage: Double {
        guard totalWork > 0 else { return 0 }
        return Double(completedWork) / Double(totalWork)
    }
}

/// Card showing a single student's progress on work from a presentation
struct StudentProgressCard: View {
    let student: Student
    let progress: StudentWorkProgress
    let modelContext: ModelContext
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(student.fullName)
                        .font(.headline)
                    
                    if progress.hasWork {
                        HStack(spacing: 8) {
                            // Completion status
                            HStack(spacing: 4) {
                                Image(systemName: progress.isAllCompleted ? "checkmark.circle.fill" : "circle.dashed")
                                    .foregroundStyle(progress.isAllCompleted ? .green : .orange)
                                Text("\(progress.completedWork)/\(progress.totalWork)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            
                            // Progress bar
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(height: 4)
                                    
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(progress.isAllCompleted ? Color.green : Color.blue)
                                        .frame(width: geo.size.width * progress.completionPercentage, height: 4)
                                }
                            }
                            .frame(height: 4)
                        }
                    } else {
                        Text("No work assigned")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                if progress.hasWork {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                            .font(.title3)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Stats badges (when not expanded)
            if !isExpanded && progress.hasWork {
                HStack(spacing: 12) {
                    if progress.activeWork > 0 {
                        CompactStatBadge(
                            icon: "circle",
                            value: "\(progress.activeWork)",
                            color: .blue
                        )
                    }
                    
                    if progress.reviewWork > 0 {
                        CompactStatBadge(
                            icon: "eye",
                            value: "\(progress.reviewWork)",
                            color: .orange
                        )
                    }
                    
                    if progress.masteredWork > 0 {
                        CompactStatBadge(
                            icon: "star.fill",
                            value: "\(progress.masteredWork)",
                            color: .green
                        )
                    }
                    
                    if progress.needsPracticeWork > 0 {
                        CompactStatBadge(
                            icon: "repeat",
                            value: "\(progress.needsPracticeWork)",
                            color: .purple
                        )
                    }
                    
                    if progress.checkInsCount > 0 {
                        CompactStatBadge(
                            icon: "checklist",
                            value: "\(progress.checkInsCount)",
                            color: .teal
                        )
                    }
                }
            }
            
            // Expanded details
            if isExpanded && progress.hasWork {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                    
                    // Work items grouped by status
                    ForEach(WorkStatus.allCases, id: \.self) { status in
                        let statusWork = progress.workItems.filter { $0.status == status }
                        if !statusWork.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: status.iconName)
                                        .font(.caption)
                                    Text(status.rawValue.capitalized)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                }
                                .foregroundStyle(status.color)
                                
                                ForEach(statusWork) { work in
                                    WorkItemDetailRow(work: work)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(progress.isAllCompleted ? Color.green.opacity(0.3) : Color.primary.opacity(0.08), lineWidth: 1.5)
        )
    }
}

/// Compact stat badge for student progress cards
struct CompactStatBadge: View {
    let icon: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
    }
}

/// Detailed row for a work item in expanded student card
struct WorkItemDetailRow: View {
    let work: WorkModel
    
    var body: some View {
        HStack(spacing: 8) {
            // Status icon
            Image(systemName: work.status == .complete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(work.status.color)
                .font(.subheadline)
            
            // Work details
            VStack(alignment: .leading, spacing: 2) {
                Text(work.title)
                    .font(.subheadline)
                    .lineLimit(2)
                
                HStack(spacing: 6) {
                    // Kind badge
                    if let kind = work.kind {
                        HStack(spacing: 3) {
                            Image(systemName: kind.iconName)
                                .font(.caption2)
                            Text(kind.displayName)
                                .font(.caption2)
                        }
                        .foregroundStyle(kind.color)
                    }
                    
                    // Completion outcome
                    if let outcome = work.completionOutcome {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text(outcome.displayName)
                            .font(.caption2)
                            .foregroundStyle(outcome.color)
                    }
                    
                    // Due date
                    if let dueAt = work.dueAt {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text(dueAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.primary.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

