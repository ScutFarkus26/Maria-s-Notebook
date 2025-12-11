import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

struct WorkView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSize

#if os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif

    // Data sources
    @Query(sort: [
        SortDescriptor(\Student.lastName),
        SortDescriptor(\Student.firstName)
    ]) private var students: [Student]

    @Query(sort: \StudentLesson.createdAt, order: .forward) private var studentLessons: [StudentLesson]
    @Query(sort: \Lesson.name, order: .forward) private var lessons: [Lesson]
    @Query(sort: \WorkModel.createdAt, order: .reverse) private var workItems: [WorkModel]

    // UI state
    @State private var filters = WorkFilters()
    @State private var isPresentingAddWork = false
    @State private var isPresentingPrintShare = false
    @State private var printShareItem: Any? = nil
    @State private var printIsMonochrome: Bool = true
    @State private var printDenseLevel: Int = 2 // 0=normal,1=compact,2=ultra
    @State private var printPaper: String = "Letter" // or "A4"
    @State private var selectedWorkID: UUID? = nil
    @State private var isShowingStudentFilterPopover = false

    // Scene storage for persistence
    @SceneStorage("WorkView.selectedSubject") private var selectedSubjectStorage: String = ""
    @SceneStorage("WorkView.selectedStudentIDs") private var selectedStudentIDsStorage: String = ""
    @SceneStorage("WorkView.searchText") private var searchTextStorage: String = ""
    @SceneStorage("WorkView.grouping") private var groupingStorage: String = ""
    @SceneStorage("WorkView.mode") private var modeStorage: String = "items"
    @SceneStorage("WorkView.level") private var levelStorage: String = "All"
    
    private enum Mode: String { case items, planning }
    @State private var mode: Mode = .items

    // Lookup service
    private var lookupService: WorkLookupService {
        WorkLookupService(
            students: students,
            lessons: lessons,
            studentLessons: studentLessons
        )
    }
    
#if os(iOS)
    private func currentScreenWidth(_ scene: UIScene? = UIApplication.shared.connectedScenes.first) -> CGFloat {
        guard let windowScene = scene as? UIWindowScene,
              let window = windowScene.windows.first else {
            return 1024 // sensible fallback
        }
        return window.bounds.width
    }
#endif
    
    private var filteredWorks: [WorkModel] {
        let base = filters.filterWorks(
            workItems,
            studentLessonsByID: lookupService.studentLessonsByID,
            lessonsByID: lookupService.lessonsByID
        )
        switch filters.level {
        case .all:
            return base
        case .lower, .upper:
            return base.filter { work in
                let map = Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) })
                return work.participants.contains { p in
                    guard let s = map[p.studentID] else { return false }
                    return (filters.level == .lower && s.level == .lower) || (filters.level == .upper && s.level == .upper)
                }
            }
        }
    }
    
    private var studentsByID: [UUID: Student] { Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) }) }

    private func isStudentVisible(_ s: Student) -> Bool {
        let matchesLevel: Bool = {
            switch filters.level {
            case .all: return true
            case .lower: return s.level == .lower
            case .upper: return s.level == .upper
            }
        }()
        let matchesSelection = filters.selectedStudentIDs.isEmpty || filters.selectedStudentIDs.contains(s.id)
        return matchesLevel && matchesSelection
    }

    private func isParticipantVisible(_ studentID: UUID) -> Bool {
        if !filters.selectedStudentIDs.isEmpty && !filters.selectedStudentIDs.contains(studentID) { return false }
        switch filters.level {
        case .all: return true
        case .lower: return studentsByID[studentID]?.level == .lower
        case .upper: return studentsByID[studentID]?.level == .upper
        }
    }

    private var openWorks: [WorkModel] { filteredWorks.filter { $0.isOpen } }

    private var openWorksByStudentID: [UUID: [WorkModel]] {
        var map: [UUID: [WorkModel]] = [:]
        for work in openWorks {
            for p in work.participants {
                guard isParticipantVisible(p.studentID) else { continue }
                if p.completedAt == nil {
                    map[p.studentID, default: []].append(work)
                }
            }
        }
        return map
    }
    
    private func makeOverviewPrintImage(maxWidth: CGFloat = 1024) -> PlatformImage? {
        let ultra = (printDenseLevel >= 2)
        let compact = (printDenseLevel >= 1)
        let v = WorkStudentsGrid(
            summaries: workSummaries,
            openWorksByStudentID: openWorksByStudentID,
            lookupService: lookupService,
            onTapStudent: { _ in },
            onTapWork: { _ in }
        ).printableView(
            monochrome: printIsMonochrome,
            dense: compact,
            ultraDense: ultra,
            minW: ultra ? 180 : (compact ? 200 : 240),
            maxW: ultra ? 220 : (compact ? 260 : 300),
            spacing: ultra ? 8 : (compact ? 10 : 14),
            cornerRadius: ultra ? 8 : (compact ? 10 : 12),
            scale: ultra ? 0.9 : (compact ? 0.95 : 1.0)
        )
        let size = CGSize(width: maxWidth, height: 0)
        return PrintUtils.renderImage(from: v, preferredSize: size, scale: 2.0)
    }
    
#if os(macOS)
    private func exportOverviewPDF(jobTitle: String) {
        let ultra = (printDenseLevel >= 2)
        let compact = (printDenseLevel >= 1)
        // Page size for Letter/A4 at 72 dpi
        let portraitSize: CGSize = (printPaper == "A4") ? CGSize(width: 595.0, height: 842.0) : CGSize(width: 612.0, height: 792.0)
        let pageSize: CGSize = CGSize(width: portraitSize.height, height: portraitSize.width) // landscape
        // Render a single tall image first; Preview can handle long pages, but we will fit to page width.
        let view = WorkStudentsGrid(
            summaries: workSummaries,
            openWorksByStudentID: openWorksByStudentID,
            lookupService: lookupService,
            onTapStudent: { _ in },
            onTapWork: { _ in }
        ).printableView(
            monochrome: printIsMonochrome,
            dense: compact,
            ultraDense: ultra,
            minW: ultra ? 180 : (compact ? 200 : 240),
            maxW: ultra ? 220 : (compact ? 260 : 300),
            spacing: ultra ? 8 : (compact ? 10 : 14),
            cornerRadius: ultra ? 8 : (compact ? 10 : 12),
            scale: ultra ? 0.9 : (compact ? 0.95 : 1.0)
        )
        // Render to NSImage at a wide width to capture detail, then scale to page width.
        let renderWidth: CGFloat = 1800
        guard let image: NSImage = PrintUtils.renderImage(from: view, preferredSize: CGSize(width: renderWidth, height: 0), scale: 2.0) else { return }
        // Convert to CGImage for drawing
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return }
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Open Work Overview.pdf")
        guard let consumer = CGDataConsumer(url: url as CFURL), let ctx = CGContext(consumer: consumer, mediaBox: nil, nil) else { return }
        // Compute scale to fit width
        let scale = pageSize.width / CGFloat(cg.width)
        var y: CGFloat = 0
        while y < CGFloat(cg.height) {
            let remaining = CGFloat(cg.height) - y
            let sliceHeight = min(remaining, pageSize.height / scale)
            let sliceRect = CGRect(x: 0, y: CGFloat(cg.height) - y - sliceHeight, width: CGFloat(cg.width), height: sliceHeight)
            ctx.beginPDFPage([kCGPDFContextMediaBox as String: CGRect(origin: .zero, size: pageSize)] as CFDictionary)
            if let slice = cg.cropping(to: sliceRect) {
                let drawRect = CGRect(x: 0, y: 0, width: pageSize.width, height: sliceHeight * scale)
                ctx.draw(slice, in: drawRect)
            }
            ctx.endPDFPage()
            y += sliceHeight
        }
        ctx.closePDF()
        NSWorkspace.shared.open(url)
    }
#endif
    
    private var workSummaries: [StudentWorkSummary] {
        var counts: [UUID: (practice: Int, follow: Int, research: Int)] = [:]
        for work in openWorks {
            for p in work.participants {
                guard isParticipantVisible(p.studentID) else { continue }
                switch work.workType {
                case .practice:
                    if p.completedAt == nil { counts[p.studentID, default: (0,0,0)].practice += 1 }
                case .followUp:
                    if p.completedAt == nil { counts[p.studentID, default: (0,0,0)].follow += 1 }
                case .research:
                    if p.completedAt == nil { counts[p.studentID, default: (0,0,0)].research += 1 }
                }
            }
        }
        let visible = students.filter { isStudentVisible($0) }
        return visible.map { s in
            let c = counts[s.id, default: (0,0,0)]
            return StudentWorkSummary(id: s.id, student: s, practiceOpen: c.practice, followUpOpen: c.follow, researchOpen: c.research)
        }
        .sorted { lhs, rhs in
            if lhs.totalOpen == rhs.totalOpen {
                return lhs.student.fullName.localizedCaseInsensitiveCompare(rhs.student.fullName) == .orderedAscending
            }
            return lhs.totalOpen > rhs.totalOpen
        }
    }
    
    // Sync filters with scene storage
    private func syncFiltersFromStorage() {
        if let grouping = WorkFilters.Grouping(rawValue: groupingStorage) {
            filters.grouping = grouping
        }
        filters.selectedSubject = selectedSubjectStorage.isEmpty ? nil : selectedSubjectStorage
        filters.searchText = searchTextStorage
        
        // Parse student IDs
        let parts = selectedStudentIDsStorage.split(separator: ",").map { String($0) }
        let uuids = parts.compactMap { UUID(uuidString: $0) }
        filters.selectedStudentIDs = Set(uuids)
        
        if let level = WorkFilters.LevelFilter(rawValue: levelStorage) {
            filters.level = level
        }
        mode = Mode(rawValue: modeStorage) ?? .items
        if modeStorage == "overview" { modeStorage = "items" }
    }
    
    private func syncFiltersToStorage() {
        groupingStorage = filters.grouping.rawValue
        selectedSubjectStorage = filters.selectedSubject ?? ""
        searchTextStorage = filters.searchText
        selectedStudentIDsStorage = filters.selectedStudentIDs.map { $0.uuidString }.joined(separator: ",")
        levelStorage = filters.level.rawValue
        modeStorage = mode.rawValue
    }
    
    private func handleWorkSelection(_ work: WorkModel) {
        #if os(macOS)
        openWindow(id: "WorkDetailWindow", value: work.id)
        #else
        selectedWorkID = work.id
        #endif
    }
    
    private func handleToggleComplete(_ work: WorkModel) {
        work.completedAt = work.isCompleted ? nil : Date()
        do { try modelContext.save() } catch { }
    }

#if !os(macOS)
    @MainActor
    private func performAfterMenuDismiss(_ action: @escaping () -> Void) {
        // Defer state changes until after the Menu has fully dismissed to avoid
        // presenting/dismissing remote views during Menu lifetime (prevents ViewBridge disconnects).
        DispatchQueue.main.async { action() }
    }
#endif

#if !os(macOS)
    private var filtersMenu: some View {
        Menu {
            Section("Students") {
                Button("Select Students…") { performAfterMenuDismiss { isShowingStudentFilterPopover = true } }
                Button("Clear Selected") { performAfterMenuDismiss { filters.selectedStudentIDs = [] } }
            }
            Section("Level") {
                Button("All") { performAfterMenuDismiss { filters.level = .all } }
                Button("Lower") { performAfterMenuDismiss { filters.level = .lower } }
                Button("Upper") { performAfterMenuDismiss { filters.level = .upper } }
            }
            Section("Subject") {
                Button("All Subjects") { performAfterMenuDismiss { filters.selectedSubject = nil } }
                ForEach(lookupService.subjects, id: \.self) { subject in
                    Button(subject) { performAfterMenuDismiss { filters.selectedSubject = subject } }
                }
            }
            Section("Group By") {
                ForEach(WorkFilters.Grouping.allCases, id: \.self) { grouping in
                    Button(grouping.displayName) { performAfterMenuDismiss { filters.grouping = grouping } }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
    }
#endif

    var body: some View {
        mainContent
            .sheet(isPresented: $isPresentingAddWork) {
                AddWorkView {
                    isPresentingAddWork = false
                }
            }
#if os(iOS)
            .sheet(isPresented: $isPresentingPrintShare) {
                if let image = printShareItem as? UIImage {
                    ActivityView(activityItems: [image])
                } else {
                    Text("Nothing to share")
                }
            }
#endif
            .onAppear {
                syncFiltersFromStorage()
                WorkDataMaintenance.backfillParticipantsIfNeeded(using: modelContext)
                mode = Mode(rawValue: modeStorage) ?? .items
                if modeStorage == "overview" { modeStorage = "items" }
            }
            .onChange(of: filters.grouping) { _, _ in syncFiltersToStorage() }
            .onChange(of: filters.selectedSubject) { _, _ in syncFiltersToStorage() }
            .onChange(of: filters.searchText) { _, _ in syncFiltersToStorage() }
            .onChange(of: filters.selectedStudentIDs) { _, _ in syncFiltersToStorage() }
            .onChange(of: filters.level) { _, _ in syncFiltersToStorage() }
            .onChange(of: mode) { _, _ in syncFiltersToStorage() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NewWorkRequested"))) { _ in
                isPresentingAddWork = true
            }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        NavigationStack {
            layoutContent
        }
#if !os(macOS)
        .toolbar {
            if hSize == .compact {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingAddWork = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .keyboardShortcut("n", modifiers: [.command])
                }
            }
        }
        .sheet(isPresented: Binding(get: { selectedWorkID != nil }, set: { if !$0 { selectedWorkID = nil } })) {
            if let id = selectedWorkID {
                WorkDetailContainerView(workID: id) {
                    selectedWorkID = nil
                }
            } else {
                EmptyView()
            }
        }
#endif
    }
    
    @ViewBuilder
    private var layoutContent: some View {
#if os(macOS)
        regularLayout
#else
        if hSize == .compact {
            compactLayout
        } else {
            regularLayout
        }
#endif
    }
    
    // MARK: - Compact Layout (iOS)
#if !os(macOS)
    private var compactLayout: some View {
        VStack(spacing: 0) {
            WorksPlanningView()
        }
    }
#endif
    
    // MARK: - Regular Layout (macOS/iPad)
    private var regularLayout: some View {
        HStack(spacing: 0) {
            WorkViewSidebar(
                filters: $filters,
                isShowingStudentFilterPopover: $isShowingStudentFilterPopover,
                subjects: lookupService.subjects,
                students: students,
                displayName: lookupService.displayName
            )

            Divider()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    HStack(spacing: 12) {
                        PillNavButton(title: "Planning", isSelected: true) { }
                    }
                    Spacer()
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
                
                Group {
                    WorksPlanningView()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 12) {
                        
                        Button {
                            isPresentingAddWork = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: AppTheme.FontSize.titleXLarge))
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut("n", modifiers: [.command])
                    }
                    .padding()
                }
            }
        }
    }
}

#if os(iOS)
import UIKit
struct ActivityView: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
#endif

