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
    @Query(sort: [SortDescriptor(\WorkContract.id)]) private var contractsForChangeDetection: [WorkContract]
    
    // MEMORY OPTIMIZATION: Extract only IDs for change detection to avoid loading full objects
    private var studentIDs: [UUID] {
        studentsForChangeDetection.map { $0.id }
    }
    
    private var contractIDs: [UUID] {
        contractsForChangeDetection.map { $0.id }
    }

    // We keep the state here to persist it, but pass it down as a binding
    @AppStorage("StudentsRootView.mode") private var modeRaw: String = StudentMode.roster.rawValue
    
    // FIX: Add 'nonmutating' to the setter
    private var mode: StudentMode {
        get { StudentMode(rawValue: modeRaw) ?? .roster }
        set { modeRaw = newValue.rawValue }
    }

    // Workload specific state
    @State private var selectedContract: WorkContract? = nil
    
    // OPTIMIZATION: Cache workload data to avoid reloading on every view update
    @State private var cachedOpenContracts: [WorkContract] = []
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
            get: { selectedContract != nil },
            set: { if !$0 { selectedContract = nil } }
        )) {
            if let contract = selectedContract {
                WorkContractDetailSheet(contract: contract) {
                    selectedContract = nil
                }
                #if os(macOS)
                .frame(minWidth: 500, minHeight: 720)
                #else
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
            }
        }
    }

    private var workOverviewContent: some View {
        WorkloadContentView(
            openContracts: cachedOpenContracts,
            studentsByID: cachedStudents,
            lessonsByID: cachedLessons,
            onTapContract: { contract in selectedContract = contract }
        )
        .task(id: mode) {
            // Reload workload data when mode changes to workOverview
            if mode == .workOverview {
                await loadWorkloadData()
            }
        }
        .onChange(of: contractIDs) { _, _ in
            // Reload workload data when contracts change (if in workOverview mode)
            if mode == .workOverview {
                Task { @MainActor in
                    await loadWorkloadData()
                }
            }
        }
    }
    
    // MARK: - Workload Data Loading
    
    /// Loads workload data on-demand: only open contracts and related students/lessons
    @MainActor
    private func loadWorkloadData() async {
        // Fetch only open contracts (active or review status)
        let openContracts: [WorkContract]
        do {
            let activeDescriptor = FetchDescriptor<WorkContract>(
                predicate: #Predicate<WorkContract> { $0.statusRaw == "active" },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            let reviewDescriptor = FetchDescriptor<WorkContract>(
                predicate: #Predicate<WorkContract> { $0.statusRaw == "review" },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            let active = try modelContext.fetch(activeDescriptor)
            let review = try modelContext.fetch(reviewDescriptor)
            openContracts = active + review
        } catch {
            openContracts = []
        }
        
        // Collect student and lesson IDs from contracts
        var neededStudentIDs = Set<UUID>()
        var neededLessonIDs = Set<UUID>()
        
        for contract in openContracts {
            if let sid = UUID(uuidString: contract.studentID) {
                neededStudentIDs.insert(sid)
            }
            if let lid = UUID(uuidString: contract.lessonID) {
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
        cachedOpenContracts = openContracts
        cachedStudents = studentsByID
        cachedLessons = lessonsByID
    }
}

// MARK: - Workload Content View

private struct WorkloadContentView: View {
    let openContracts: [WorkContract]
    let studentsByID: [UUID: Student]
    let lessonsByID: [UUID: Lesson]
    let onTapContract: (WorkContract) -> Void
    
    private var openByStudent: [UUID: [WorkContract]] {
        var result: [UUID: [WorkContract]] = [:]
        for contract in openContracts {
            if let sid = UUID(uuidString: contract.studentID) {
                result[sid, default: []].append(contract)
            }
        }
        return result
    }
    
    private var counts: [UUID: (practice: Int, follow: Int, research: Int)] {
        var result: [UUID: (practice: Int, follow: Int, research: Int)] = [:]
        for contract in openContracts {
            guard let sid = UUID(uuidString: contract.studentID) else { continue }
            
            switch contract.kind {
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
            openContractsByStudentID: openByStudent,
            lessonsByID: lessonsByID,
            onTapStudent: { _ in
                // In Workload view, tapping a student could perhaps filter or open details
                // For now, we leave it as is or implement specific workload navigation
            },
            onTapContract: onTapContract
        )
    }
}

