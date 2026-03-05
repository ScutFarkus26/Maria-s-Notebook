import OSLog
import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
import PDFKit
#endif

struct WorksAgendaView: View {
    private static let logger = Logger.work

    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Environment(SaveCoordinator.self) private var saveCoordinator
    @Environment(RestoreCoordinator.self) private var restoreCoordinator

    @Query(filter: #Predicate<WorkModel> { $0.statusRaw != "complete" }, sort: [SortDescriptor(\WorkModel.createdAt, order: .reverse)])
    private var openWork: [WorkModel]
    
    @Query(
        filter: #Predicate<WorkCheckIn> { $0.statusRaw == "Scheduled" },
        sort: [SortDescriptor(\WorkCheckIn.date)]
    )
    private var scheduledCheckIns: [WorkCheckIn]
    
    // MEMORY OPTIMIZATION: Use lightweight queries for change detection only (IDs only)
    // Extract IDs immediately to avoid retaining full objects - significantly reduces memory usage
    @Query(sort: [SortDescriptor(\Lesson.id)]) private var lessonsForChangeDetection: [Lesson]
    @Query(sort: [SortDescriptor(\Student.id)]) private var studentsForChangeDetection: [Student]
    
    // MEMORY OPTIMIZATION: Extract only IDs for change detection to avoid loading full objects
    private var lessonIDs: [UUID] {
        lessonsForChangeDetection.map { $0.id }
    }
    
    private var studentIDs: [UUID] {
        studentsForChangeDetection.map { $0.id }
    }
    
    // Lazy-loaded caches (only populated when needed)
    @State private var lessonsByIDCache: [UUID: Lesson] = [:]
    @State private var studentsByIDCache: [UUID: Student] = [:]

    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames) private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"
    @AppStorage(UserDefaultsKeys.workAgendaHideScheduled) private var hideScheduled: Bool = false

    @State private var sortMode: WorkAgendaSortMode = .lesson
    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var calendarHeightRatio: CGFloat = 0.5 // 50% calendar, 50% open work
    @State private var isCalendarMinimized: Bool = false
    @State private var calendarStartDate: Date = AppCalendar.startOfDay(Date())

    @State private var selectedWorkID: UUID?

    private struct SelectionToken: Identifiable, Equatable { let id: UUID; let workID: UUID }
    @State private var selected: SelectionToken?

    // MEMORY OPTIMIZATION: Load lessons and students on-demand based on contracts
    private var lessonsByID: [UUID: Lesson] { lessonsByIDCache }
    private var studentsByID: [UUID: Student] { studentsByIDCache }

    /// Combined trigger for data reload - changes when any relevant data changes
    private var dataReloadTrigger: Int {
        var hasher = Hasher()
        hasher.combine(openWork.map { $0.id })
        hasher.combine(lessonIDs)
        hasher.combine(studentIDs)
        hasher.combine(showTestStudents)
        hasher.combine(testStudentNamesRaw)
        return hasher.finalize()
    }
    
    private func loadLessonsAndStudentsIfNeeded() {
        // Collect IDs from open work
        var neededLessonIDs = Set<UUID>()
        var neededStudentIDs = Set<UUID>()
        
        for work in openWork {
            if let lid = UUID(uuidString: work.lessonID) {
                neededLessonIDs.insert(lid)
            }
            if let sid = UUID(uuidString: work.studentID) {
                neededStudentIDs.insert(sid)
            }
        }
        
        // Load only needed lessons
        // NOTE: SwiftData #Predicate doesn't support capturing local Set variables,
        // so we fetch all and filter in memory
        // Use uniquingKeysWith to handle CloudKit sync duplicates
        if !neededLessonIDs.isEmpty {
            let all: [Lesson]
            do {
                all = try modelContext.fetch(FetchDescriptor<Lesson>())
            } catch {
                Self.logger.warning("Failed to fetch lessons: \(error)")
                all = []
            }
            let filtered = all.filter { neededLessonIDs.contains($0.id) }
            lessonsByIDCache = Dictionary(filtered.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        } else {
            lessonsByIDCache = [:]
        }

        // Load only needed students
        // NOTE: SwiftData #Predicate doesn't support capturing local Set variables,
        // so we fetch all and filter in memory
        // Use uniquingKeysWith to handle CloudKit sync duplicates
        if !neededStudentIDs.isEmpty {
            let all: [Student]
            do {
                all = try modelContext.fetch(FetchDescriptor<Student>())
            } catch {
                Self.logger.warning("Failed to fetch students: \(error)")
                all = []
            }
            let filtered = all.filter { neededStudentIDs.contains($0.id) }
            // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
            let visible = TestStudentsFilter.filterVisible(filtered, show: showTestStudents, namesRaw: testStudentNamesRaw).uniqueByID
            studentsByIDCache = Dictionary(visible.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        } else {
            studentsByIDCache = [:]
        }
    }

    var body: some View {
        Group {
            if restoreCoordinator.isRestoring {
                VStack(spacing: 16) {
                    ProgressView().controlSize(.large)
                    Text("Restoring data…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        // Top: Open Work grid
                        VStack(alignment: .leading, spacing: 8) {
                            header
                            Divider()
                            OpenWorkGrid(
                                works: openWorksFiltered(),
                                lessonsByID: lessonsByID,
                                studentsByID: studentsByID,
                                sortMode: sortMode,
                                onOpen: openDetail,
                                onMarkCompleted: markCompleted,
                                onScheduleToday: scheduleToday
                            )
                        }
                        .frame(height: geo.size.height * (isCalendarMinimized ? 1.0 : (1 - calendarHeightRatio)))

                        if !isCalendarMinimized {
                            Divider()

                            // Bottom: Calendar pane
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 12) {
                                    Button {
                                        moveCalendarStart(bySchoolDays: -UIConstants.planningNavigationStepSchoolDays)
                                    } label: {
                                        Image(systemName: "chevron.left")
                                    }
                                    .buttonStyle(.plain)

                                    Text("Planning Calendar")
                                        .font(.title3.weight(.semibold))

                                    Button {
                                        moveCalendarStart(bySchoolDays: UIConstants.planningNavigationStepSchoolDays)
                                    } label: {
                                        Image(systemName: "chevron.right")
                                    }
                                    .buttonStyle(.plain)

                                    Spacer()

                                    Button("Today") {
                                        calendarStartDate = AppCalendar.startOfDay(Date())
                                    }
                                    .font(AppTheme.ScaledFont.captionSemibold)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.primary.opacity(0.08), in: Capsule())
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                                WorkAgendaCalendarPane(startDate: calendarStartDate, daysCount: 10)
                                    .frame(maxHeight: .infinity)
                            }
                            .frame(height: geo.size.height * calendarHeightRatio)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                }
                .navigationTitle("Work Agenda")
                .sheet(item: $selected, onDismiss: { selected = nil }) { token in
                    let id = token.workID
                    let fetch = FetchDescriptor<WorkModel>(predicate: #Predicate { $0.id == id })
                    if let w = modelContext.safeFetchFirst(fetch) {
                        WorkDetailView(workID: w.id)
                            .id(token.id)
                    } else {
                        ContentUnavailableView("Work not found", systemImage: "exclamationmark.triangle")
                    }
                }
            }
        }
        .onAppear {
            loadLessonsAndStudentsIfNeeded()
        }
        .onChange(of: dataReloadTrigger) { _, _ in
            loadLessonsAndStudentsIfNeeded()
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            ViewHeader(title: "Open Work") {
                HStack(spacing: 12) {
                    #if os(iOS)
                    Button {
                        adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isCalendarMinimized.toggle()
                        }
                    } label: {
                        Image(systemName: isCalendarMinimized ? "calendar" : "calendar.badge.minus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .background(Color.primary.opacity(0.1))
                            .clipShape(Circle())
                    }
                    #endif
                    Picker("Sort", selection: $sortMode) {
                        ForEach(WorkAgendaSortMode.allCases) { m in Text(m.rawValue).tag(m) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 420)
                    
                    Button {
                        hideScheduled.toggle()
                    } label: {
                        Image(systemName: hideScheduled ? "calendar.badge.minus" : "calendar")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(hideScheduled ? "Show scheduled work" : "Hide scheduled work")
                    #if os(macOS)
                    Button {
                        printWorkView()
                    } label: {
                        Label("Print", systemImage: "printer")
                    }
                    .help("Print open work")
                    Button {
                        exportWorkPDF()
                    } label: {
                        Label("Export PDF", systemImage: "square.and.arrow.down")
                    }
                    .help("Export open work to PDF")
                    #endif
                }
            }
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search students or lessons", text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        searchDebounceTask?.cancel()
                        debouncedSearchText = searchText
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .onChange(of: searchText) { _, newValue in
                searchDebounceTask?.cancel()
                searchDebounceTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250)) // 250ms debounce
                    guard !Task.isCancelled else { return }
                    debouncedSearchText = newValue
                }
            }
        }
    }

    // MARK: - Data helpers
    
    private func openWorksFiltered() -> [WorkModel] {
        // Filter open work in memory (anything NOT .complete)
        var works = openWork
        
        // Hide scheduled work if enabled
        if hideScheduled {
            let scheduledWorkIDs = Set(scheduledCheckIns.compactMap { UUID(uuidString: $0.workID) })
            works = works.filter { !scheduledWorkIDs.contains($0.id) }
        }
        
        // Optional search (use debounced text for filtering)
        if !debouncedSearchText.trimmed().isEmpty {
            let query = debouncedSearchText.lowercased()
            works = works.filter { w in
                var hay: [String] = []
                hay.append(lessonTitle(forLessonID: w.lessonID))
                if let sid = UUID(uuidString: w.studentID), let s = studentsByID[sid] {
                    hay.append(s.firstName)
                    hay.append(s.lastName)
                    hay.append(s.fullName)
                    hay.append(StudentFormatter.displayName(for: s))
                }
                return hay.joined(separator: " ").lowercased().contains(query)
            }
        }
        return works
    }

    private func lessonTitle(forLessonID lessonID: String) -> String {
        if let lid = UUID(uuidString: lessonID), let lesson = lessonsByID[lid] {
            let name = lesson.name.trimmed()
            if !name.isEmpty { return name }
        }
        return "Lesson \(String(lessonID.prefix(6)))"
    }

    #if os(macOS)
    private func makePrintItems(from works: [WorkModel]) -> [WorkPDFRenderer.PrintItem] {
        works.map { w in
            let title = lessonTitle(forLessonID: w.lessonID)
            let student = (UUID(uuidString: w.studentID)).flatMap { studentsByID[$0] }.map(studentPrintName(for:)) ?? "Student"
            return WorkPDFRenderer.PrintItem(
                id: w.id,
                lessonTitle: title,
                studentName: student,
                statusLabel: statusLabel(for: w),
                ageDays: ageDays(for: w),
                dueAt: w.dueAt,
                needsAttention: needsAttention(for: w)
            )
        }
    }
    #endif

    private func studentPrintName(for student: Student) -> String {
        let parts = student.fullName.split(separator: " ")
        guard let first = parts.first else { return student.fullName }
        let lastInitial = parts.dropFirst().first?.first.map { String($0) } ?? ""
        return lastInitial.isEmpty ? String(first) : "\(first) \(lastInitial)."
    }

    private func statusLabel(for w: WorkModel) -> String {
        switch w.status {
        case .active: return "Practice"
        case .review: return "Follow-Up"
        case .complete: return "Completed"
        }
    }

    private func ageDays(for w: WorkModel) -> Int {
        AppCalendar.shared.dateComponents([.day], from: AppCalendar.startOfDay(w.createdAt), to: AppCalendar.startOfDay(Date())).day ?? 0
    }

    private func needsAttention(for w: WorkModel) -> Bool {
        if let due = w.dueAt, AppCalendar.startOfDay(due) < AppCalendar.startOfDay(Date()) { return true }
        if let lastNoteDate = (w.unifiedNotes ?? []).map({ max($0.updatedAt, $0.createdAt) }).max() {
            let days = AppCalendar.shared.dateComponents([.day], from: AppCalendar.startOfDay(lastNoteDate), to: AppCalendar.startOfDay(Date())).day ?? 0
            if days >= 10 { return true }
        }
        return LessonAgeHelper.schoolDaysSinceCreation(createdAt: w.createdAt, asOf: Date(), using: modelContext, calendar: calendar) >= 10
    }

    // MARK: - Calendar Navigation

    private func moveCalendarStart(bySchoolDays delta: Int) {
        guard delta != 0 else { return }
        var remaining = abs(delta)
        var cursor = AppCalendar.startOfDay(calendarStartDate)
        let step = delta > 0 ? 1 : -1
        while remaining > 0 {
            cursor = calendar.date(byAdding: .day, value: step, to: cursor) ?? cursor
            if !SchoolDayChecker.isNonSchoolDay(cursor, using: modelContext) { remaining -= 1 }
        }
        calendarStartDate = cursor
    }

    // MARK: - Actions
    private func openDetail(_ w: WorkModel) {
        // Force save before opening
        do {
            try modelContext.save()
        } catch {
            Self.logger.warning("Failed to save context: \(error)")
        }

        selected = nil
        let token = SelectionToken(id: UUID(), workID: w.id)
        Task { @MainActor in
            selected = token
        }
    }

    private func markCompleted(_ w: WorkModel) {
        w.status = .complete
        _ = saveCoordinator.save(modelContext, reason: "Mark work completed")
        HapticService.shared.notification(.success)
    }

    private func scheduleToday(_ w: WorkModel) {
        let today = AppCalendar.startOfDay(Date())
        // Phase 6: Update or create a WorkCheckIn for this work
        let workID: UUID = w.id
        let workIDString = workID.uuidString
        var fetch = FetchDescriptor<WorkCheckIn>(
            predicate: #Predicate<WorkCheckIn> { $0.workID == workIDString },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        fetch.fetchLimit = 1
        do {
            if let first = try modelContext.fetch(fetch).first {
                first.date = today
            } else {
                let item = WorkCheckIn(id: UUID(), workID: workID, date: today, status: .scheduled, purpose: "progressCheck")
                modelContext.insert(item)
            }
        } catch {
            Self.logger.warning("Failed to fetch WorkCheckIn: \(error)")
            // Create new check-in as fallback
            let item = WorkCheckIn(id: UUID(), workID: workID, date: today, status: .scheduled, purpose: "progressCheck")
            modelContext.insert(item)
        }
        w.dueAt = today
        _ = saveCoordinator.save(modelContext, reason: "Quick schedule today")
    }

    #if os(macOS)
    private func printWorkView() {
        let works = openWorksFiltered()
        let items = makePrintItems(from: works)
        guard let pdfData = WorkPDFRenderer.renderPDF(items: items, sortMode: sortMode, searchText: debouncedSearchText) else {
            NSSound.beep()
            return
        }

        let printInfo = WorkPDFRenderer.configuredPrintInfo()
        if let doc = PDFDocument(data: pdfData),
           let operation = doc.printOperation(for: printInfo, scalingMode: .pageScaleToFit, autoRotate: false) {
            operation.showsPrintPanel = true
            operation.showsProgressPanel = true
            operation.run()
        }
    }

    private func exportWorkPDF() {
        let works = openWorksFiltered()
        let items = makePrintItems(from: works)
        let currentSortMode = sortMode
        let currentSearchText = debouncedSearchText

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Open Work.pdf"
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let pdfData = WorkPDFRenderer.renderPDF(items: items, sortMode: currentSortMode, searchText: currentSearchText) else {
                NSSound.beep()
                return
            }
            do {
                try pdfData.write(to: url, options: .atomic)
            } catch {
                NSSound.beep()
            }
        }
    }
    #endif
}

#Preview {
    // Encapsulate data setup in a closure to avoid Void return statements in ViewBuilder
    let container: ModelContainer = {
        let schema = AppSchema.schema
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Failed to create preview container: \(error)")
        }
        let ctx = container.mainContext
        
        let s = Student(firstName: "Ada", lastName: "Lovelace", birthday: Date(), level: .upper)
        let l = Lesson(name: "Long Division", subject: "Math", group: "Ops", subheading: "", writeUp: "")
        ctx.insert(s)
        ctx.insert(l)
        let w = WorkModel(status: .active, studentID: s.id.uuidString, lessonID: l.id.uuidString)
        ctx.insert(w)
        return container
    }()

    WorksAgendaView()
        .previewEnvironment(using: container)
        .environment(SaveCoordinator.preview)
}
