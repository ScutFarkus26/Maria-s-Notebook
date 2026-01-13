import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// Public enum so both views can see it
enum StudentMode: String, CaseIterable, Identifiable {
    case roster = "Roster"
    case age = "Age"
    case birthday = "Birthday"
    case lastLesson = "Last Lesson"
    case workOverview = "Workload"
    case observationHeatmap = "Observations"
    var id: String { rawValue }
}

struct StudentsRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appRouter) private var appRouter
    
    // OPTIMIZATION: Use lightweight queries for change detection only (IDs only)
    // Extract IDs immediately to avoid retaining full objects - significantly reduces memory usage
    @Query(sort: [SortDescriptor(\Student.id)]) private var studentsForChangeDetection: [Student]
    @Query(sort: [SortDescriptor(\WorkModel.id)]) private var workForChangeDetection: [WorkModel]
    
    // MEMORY OPTIMIZATION: Extract only IDs for change detection to avoid loading full objects
    private var studentIDs: [UUID] {
        studentsForChangeDetection.map { $0.id }
    }
    
    private var workIDs: [UUID] {
        workForChangeDetection.map { $0.id }
    }

    // We keep the state here to persist it, but pass it down as a binding
    @AppStorage("StudentsRootView.mode") private var modeRaw: String = StudentMode.roster.rawValue
    
    // FIX: Add 'nonmutating' to the setter
    private var mode: StudentMode {
        get { StudentMode(rawValue: modeRaw) ?? .roster }
        set { modeRaw = newValue.rawValue }
    }

    // Workload specific state
    @State private var selectedWork: WorkModel? = nil
    
    // OPTIMIZATION: Cache workload data to avoid reloading on every view update
    @State private var cachedOpenWork: [WorkModel] = []
    @State private var cachedStudents: [UUID: Student] = [:]
    @State private var cachedLessons: [UUID: Lesson] = [:]

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        StudentsView(
            mode: Binding(get: { mode }, set: { newValue in modeRaw = newValue.rawValue }),
            workloadContent: {
                workOverviewContent
            }
        )
        .sheet(isPresented: Binding(
            get: { selectedWork != nil },
            set: { if !$0 { selectedWork = nil } }
        )) {
            if let work = selectedWork {
                WorkModelDetailSheet(workID: work.id) {
                    selectedWork = nil
                }
                #if os(macOS)
                .frame(minWidth: 500, minHeight: 720)
                #else
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
            } else {
                // Keep the sheet alive instead of returning EmptyView to avoid ViewBridge cancellation
                ProgressView("Loading…")
                    .frame(minWidth: 320, minHeight: 240)
                    .task {
                        // Dismiss if the work is no longer available after a brief delay
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                        if selectedWork != nil {
                            selectedWork = nil
                        }
                    }
            }
        }
    }

    private var workOverviewContent: some View {
        WorkloadContentView(
            openWork: cachedOpenWork,
            studentsByID: cachedStudents,
            lessonsByID: cachedLessons,
            onTapWork: { work in selectedWork = work }
        )
        .task(id: mode) {
            // Reload workload data when mode changes to workOverview
            if mode == .workOverview {
                await loadWorkloadData()
            }
        }
        .onChange(of: workIDs) { _, _ in
            // Reload workload data when work changes (if in workOverview mode)
            if mode == .workOverview {
                Task { @MainActor in
                    await loadWorkloadData()
                }
            }
        }
    }
    
    // MARK: - Workload Data Loading
    
    /// Loads workload data on-demand: only open work and related students/lessons
    @MainActor
    private func loadWorkloadData() async {
        // Fetch only open work (statusRaw != "complete" means active or review status)
        let openWork: [WorkModel]
        do {
            let descriptor = FetchDescriptor<WorkModel>(
                predicate: #Predicate<WorkModel> { $0.statusRaw != "complete" },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            openWork = try modelContext.fetch(descriptor)
        } catch {
            openWork = []
        }
        
        // Collect student and lesson IDs from work
        var neededStudentIDs = Set<UUID>()
        var neededLessonIDs = Set<UUID>()
        
        for work in openWork {
            if let sid = UUID(uuidString: work.studentID) {
                neededStudentIDs.insert(sid)
            }
            if let lid = UUID(uuidString: work.lessonID) {
                neededLessonIDs.insert(lid)
            }
        }
        
        // Fetch only needed students
        var studentsByID: [UUID: Student] = [:]
        if !neededStudentIDs.isEmpty {
            let studentsDescriptor = FetchDescriptor<Student>(
                predicate: #Predicate { neededStudentIDs.contains($0.id) }
            )
            let fetchedStudents = modelContext.safeFetch(studentsDescriptor)
            let visibleStudents = TestStudentsFilter.filterVisible(fetchedStudents)
            studentsByID = Dictionary(uniqueKeysWithValues: visibleStudents.map { ($0.id, $0) })
        }
        
        // Fetch only needed lessons
        var lessonsByID: [UUID: Lesson] = [:]
        if !neededLessonIDs.isEmpty {
            let lessonsDescriptor = FetchDescriptor<Lesson>(
                predicate: #Predicate { neededLessonIDs.contains($0.id) }
            )
            let fetchedLessons = modelContext.safeFetch(lessonsDescriptor)
            lessonsByID = Dictionary(uniqueKeysWithValues: fetchedLessons.map { ($0.id, $0) })
        }
        
        // Update cache
        cachedOpenWork = openWork
        cachedStudents = studentsByID
        cachedLessons = lessonsByID
    }
}

// MARK: - Workload Content View
private struct WorkloadContentView: View {
    let openWork: [WorkModel]
    let studentsByID: [UUID: Student]
    let lessonsByID: [UUID: Lesson]
    let onTapWork: (WorkModel) -> Void
    
    private var openByStudent: [UUID: [WorkModel]] {
        var result: [UUID: [WorkModel]] = [:]
        for work in openWork {
            if let sid = UUID(uuidString: work.studentID) {
                result[sid, default: []].append(work)
            }
        }
        return result
    }
    
    private var counts: [UUID: (practice: Int, follow: Int, research: Int)] {
        var result: [UUID: (practice: Int, follow: Int, research: Int)] = [:]
        for work in openWork {
            guard let sid = UUID(uuidString: work.studentID) else { continue }
            
            switch work.kind {
            case .practiceLesson:
                result[sid, default: (0,0,0)].practice += 1
            case .followUpAssignment:
                result[sid, default: (0,0,0)].follow += 1
            case .research:
                result[sid, default: (0,0,0)].research += 1
            case nil:
                result[sid, default: (0,0,0)].follow += 1
            }
        }
        return result
    }
    
    private var summaries: [StudentWorkSummary] {
        let countsMap = counts
        return studentsByID.values.map { s in
            let c = countsMap[s.id, default: (0,0,0)]
            return StudentWorkSummary(id: s.id, student: s, practiceOpen: c.practice, followUpOpen: c.follow, researchOpen: c.research)
        }
        .sorted { lhs, rhs in
            if lhs.totalOpen == rhs.totalOpen {
                return lhs.student.fullName.localizedCaseInsensitiveCompare(rhs.student.fullName) == .orderedAscending
            }
            return lhs.totalOpen > rhs.totalOpen
        }
    }
    
    var body: some View {
        WorkStudentsGrid(
            summaries: summaries,
            openWorkByStudentID: openByStudent,
            lessonsByID: lessonsByID,
            onTapStudent: { _ in
                // In Workload view, tapping a student could perhaps filter or open details
                // For now, we leave it as is or implement specific workload navigation
            },
            onTapWork: onTapWork
        )
    }
}


