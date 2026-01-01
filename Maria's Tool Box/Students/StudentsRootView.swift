import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// Public enum so both views can see it
enum StudentMode: String, CaseIterable, Identifiable {
    case roster = "Roster"
    case attendance = "Attendance"
    case workOverview = "Workload"
    var id: String { rawValue }
}

struct StudentsRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var students: [Student]
    @Query(sort: \StudentLesson.createdAt, order: .forward) private var studentLessons: [StudentLesson]
    @Query(sort: \Lesson.name, order: .forward) private var lessons: [Lesson]
    
    // Querying WorkContract as per previous refactor
    @Query(sort: \WorkContract.createdAt, order: .reverse) private var workContracts: [WorkContract]

    // We keep the state here to persist it, but pass it down as a binding
    @AppStorage("StudentsRootView.mode") private var modeRaw: String = StudentMode.roster.rawValue
    
    // FIX: Add 'nonmutating' to the setter
    private var mode: StudentMode {
        get { StudentMode(rawValue: modeRaw) ?? .roster }
        nonmutating set { modeRaw = newValue.rawValue }
    }

    // Workload specific state
    @State private var selectedContract: WorkContract? = nil

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        StudentsView(
            mode: Binding(get: { mode }, set: { mode = $0 }),
            attendanceContent: {
                AttendanceView()
            },
            workloadContent: {
                workOverviewContent
            }
        )
        // Global sheets that might apply to multiple contexts (like opening a contract detail)
        .sheet(item: $selectedContract) { contract in
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
        // Allow external triggers to jump straight to Attendance mode
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenAttendanceRequested"))) { _ in
            modeRaw = StudentMode.attendance.rawValue
        }
    }

    private var workOverviewContent: some View {
        let openContracts = workContracts.filter { $0.isOpen }
        
        let lessonsByID = Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })
        
        var openByStudent: [UUID: [WorkContract]] = [:]
        
        for contract in openContracts {
            if let sid = UUID(uuidString: contract.studentID) {
                openByStudent[sid, default: []].append(contract)
            }
        }
        
        var counts: [UUID: (practice: Int, follow: Int, research: Int)] = [:]
        for contract in openContracts {
            guard let sid = UUID(uuidString: contract.studentID) else { continue }
            
            switch contract.kind {
            case .practiceLesson:
                counts[sid, default: (0,0,0)].practice += 1
            case .followUpAssignment:
                counts[sid, default: (0,0,0)].follow += 1
            case .research:
                counts[sid, default: (0,0,0)].research += 1
            case nil:
                counts[sid, default: (0,0,0)].follow += 1
            }
        }
        
        let summaries: [StudentWorkSummary] = students.map { s in
            let c = counts[s.id, default: (0,0,0)]
            return StudentWorkSummary(id: s.id, student: s, practiceOpen: c.practice, followUpOpen: c.follow, researchOpen: c.research)
        }
        .sorted { lhs, rhs in
            if lhs.totalOpen == rhs.totalOpen {
                return lhs.student.fullName.localizedCaseInsensitiveCompare(rhs.student.fullName) == .orderedAscending
            }
            return lhs.totalOpen > rhs.totalOpen
        }

        return WorkStudentsGrid(
            summaries: summaries,
            openContractsByStudentID: openByStudent,
            lessonsByID: lessonsByID,
            onTapStudent: { _ in
                // In Workload view, tapping a student could perhaps filter or open details
                // For now, we leave it as is or implement specific workload navigation
            },
            onTapContract: { contract in selectedContract = contract }
        )
    }
}
