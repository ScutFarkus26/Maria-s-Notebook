import SwiftUI
import SwiftData

/// Shows all presentations with their follow-up work and practice outcomes
struct PresentationProgressListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LessonAssignment.scheduledForDay, order: .reverse) private var allPresentations: [LessonAssignment]
    
    @State private var searchText = ""
    @State private var filterState: PresentationState?
    @State private var selectedPresentation: LessonAssignment?
    @State private var showingProgressDetail = false
    
    private var filteredPresentations: [LessonAssignment] {
        var presentations = allPresentations
        
        // Filter by state
        if let filterState = filterState {
            presentations = presentations.filter { $0.state == filterState }
        }
        
        // Filter by search
        if !searchText.isEmpty {
            presentations = presentations.filter { presentation in
                if let lesson = presentation.fetchLesson(from: modelContext) {
                    return lesson.title.localizedCaseInsensitiveContains(searchText)
                }
                return false
            }
        }
        
        return presentations
    }
    
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
            List(filteredPresentations) { presentation in
                PresentationProgressRow(presentation: presentation)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedPresentation = presentation
                        showingProgressDetail = true
                    }
            }
            .searchable(text: $searchText, prompt: "Search lessons...")
            .overlay {
                if filteredPresentations.isEmpty {
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
    }
}

/// Row showing presentation preview with stats
struct PresentationProgressRow: View {
    @Environment(\.modelContext) private var modelContext
    let presentation: LessonAssignment
    
    @State private var lesson: Lesson?
    @State private var workStats: (completed: Int, total: Int) = (0, 0)
    @State private var practiceCount: Int = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Lesson title and date
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lesson?.title ?? "Unknown Lesson")
                        .font(.headline)
                    
                    if let date = presentation.scheduledForDay {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                // State badge
                Text(presentation.state.rawValue.capitalized)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(stateBadgeColor.opacity(0.2))
                    .foregroundStyle(stateBadgeColor)
                    .clipShape(Capsule())
            }
            
            // Students
            if !presentation.studentIDs.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(presentation.studentIDs.count) students")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Stats badges
            HStack(spacing: 12) {
                StatBadge(
                    icon: "doc.text.fill",
                    value: "\(workStats.total)",
                    label: "Work Items",
                    color: .blue
                )
                
                if workStats.total > 0 {
                    StatBadge(
                        icon: "checkmark.circle.fill",
                        value: "\(workStats.completed)",
                        label: "Completed",
                        color: .green
                    )
                }
                
                if practiceCount > 0 {
                    StatBadge(
                        icon: "figure.run",
                        value: "\(practiceCount)",
                        label: "Practice",
                        color: .orange
                    )
                }
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 8)
        .task {
            loadData()
        }
    }
    
    private var stateBadgeColor: Color {
        switch presentation.state {
        case .presented: return .green
        case .scheduled: return .blue
        case .draft: return .gray
        }
    }
    
    private func loadData() {
        lesson = presentation.fetchLesson(from: modelContext)
        workStats = presentation.workCompletionStats(from: modelContext)
        practiceCount = presentation.fetchRelatedPracticeSessions(from: modelContext).count
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
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header section
                    VStack(alignment: .leading, spacing: 12) {
                        Text(lesson?.title ?? "Unknown Lesson")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        HStack {
                            if let date = presentation.scheduledForDay {
                                Label(
                                    date.formatted(date: .abbreviated, time: .omitted),
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
                    
                    // Students section
                    if !students.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Students", systemImage: "person.2.fill")
                                .font(.headline)
                            
                            FlowLayout(spacing: 8) {
                                ForEach(students) { student in
                                    Text(student.fullName)
                                        .font(.subheadline)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.blue.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Work items section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Follow-Up Work", systemImage: "doc.text.fill")
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
                    if presentation.needsReview || presentation.needsReinforcement || presentation.needsFollowUp {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Flags", systemImage: "flag.fill")
                                .font(.headline)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                if presentation.needsReview {
                                    FlagBadge(text: "Needs Review", color: .orange)
                                }
                                if presentation.needsReinforcement {
                                    FlagBadge(text: "Needs Reinforcement", color: .red)
                                }
                                if presentation.needsFollowUp {
                                    FlagBadge(text: "Needs Follow-Up", color: .blue)
                                }
                            }
                        }
                    }
                    
                    // Notes
                    if let notes = presentation.notes, !notes.isEmpty {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Notes", systemImage: "note.text")
                                .font(.headline)
                            
                            Text(notes)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Presentation Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone()
                    }
                }
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
    
    @MainActor
    private func loadData() {
        lesson = presentation.fetchLesson(from: modelContext)
        students = presentation.fetchStudents(from: modelContext)
        workItems = presentation.fetchRelatedWork(from: modelContext)
        practiceSessions = presentation.fetchRelatedPracticeSessions(from: modelContext)
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
                Text(session.title)
                    .font(.subheadline)
                
                Text(session.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if let duration = session.durationMinutes {
                Text("\(duration) min")
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

// Simple flow layout for wrapping views
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var frames: [CGRect] = []
        var size: CGSize = .zero
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                
                frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}
