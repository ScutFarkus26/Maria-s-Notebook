import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Top-level view for managing and browsing students with a unified sidebar.
struct StudentsView<AttendanceContent: View, WorkloadContent: View>: View {
    @Binding var mode: StudentMode
    @ViewBuilder let attendanceContent: AttendanceContent
    @ViewBuilder let workloadContent: WorkloadContent
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appRouter) private var appRouter
    @Environment(\.calendar) private var calendar
    
    // OPTIMIZATION: Students always needed in roster mode, so keep @Query
    @Query private var students: [Student]
    
    // OPTIMIZATION: Use lightweight queries for change detection only (IDs only)
    // Extract IDs immediately to avoid retaining full objects - significantly reduces memory usage
    @Query(sort: [SortDescriptor(\AttendanceRecord.id)]) private var attendanceRecordsForChangeDetection: [AttendanceRecord]
    @Query(sort: [SortDescriptor(\StudentLesson.id)]) private var studentLessonsForChangeDetection: [StudentLesson]
    @Query(sort: [SortDescriptor(\Lesson.id)]) private var lessonsForChangeDetection: [Lesson]
    
    // MEMORY OPTIMIZATION: Extract only IDs for change detection to avoid loading full objects
    private var attendanceRecordIDs: [UUID] {
        attendanceRecordsForChangeDetection.map { $0.id }
    }
    
    private var studentLessonIDs: [UUID] {
        studentLessonsForChangeDetection.map { $0.id }
    }
    
    private var lessonIDs: [UUID] {
        lessonsForChangeDetection.map { $0.id }
    }
    
    // OPTIMIZATION: Cache data loaded on-demand based on mode and filters
    @State private var cachedAttendanceRecords: [AttendanceRecord] = []
    @State private var cachedStudentLessons: [StudentLesson] = []
    @State private var cachedLessons: [UUID: Lesson] = [:]
    
    private let viewModel = StudentsViewModel()

    // MARK: - App Storage for Roster Mode
    @AppStorage("StudentsView.sortOrder") private var studentsSortOrderRaw: String = "alphabetical"
    @AppStorage("StudentsView.selectedFilter") private var studentsFilterRaw: String = "all"
    @AppStorage("StudentsView.presentNow.excludedNames") private var presentNowExcludedNamesRaw: String = "danny de berry,lil dan d"
    @AppStorage("General.showTestStudents") private var showTestStudents: Bool = false
    @AppStorage("General.testStudentNames") private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    // MARK: - State for Roster Mode
    @State private var showingAddStudent = false
    @State private var selectedStudentID: UUID? = nil
    @State private var isShowingSaveError: Bool = false
    @State private var saveErrorMessage: String = ""
    
    // MARK: - State for CSV Import
    @State private var showingStudentCSVImporter: Bool = false
    @State private var importAlert: ImportAlert? = nil
    @State private var mappingHeaders: [String] = []
    @State private var pendingMapping: StudentCSVImporter.Mapping? = nil
    @State private var pendingFileURL: URL? = nil
    @State private var pendingParsedImport: StudentCSVImporter.Parsed? = nil
    @State private var showingMappingSheet: Bool = false
    @State private var isParsing: Bool = false
    @State private var parsingTask: Task<Void, Never>? = nil

    private struct ImportAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    // MARK: - Computed Properties (Roster)
    private var sortOrder: SortOrder {
        switch studentsSortOrderRaw {
        case "manual": return .manual
        case "age": return .age
        case "birthday": return .birthday
        case "lastLesson": return .lastLesson
        default: return .alphabetical
        }
    }

    private var selectedFilter: StudentsFilter {
        switch studentsFilterRaw {
        case "upper": return .upper
        case "lower": return .lower
        case "presentNow": return .presentNow
        case "presentToday": return .presentNow
        default: return .all
        }
    }
    
    private var levelFilters: [StudentsFilter] { [.upper, .lower] }

    // Logic helpers
    private var excludedPresentNowNames: Set<String> {
        let lower = presentNowExcludedNamesRaw.lowercased()
        let parts = lower.split(whereSeparator: { ch in ch == "," || ch == ";" || ch.isNewline })
        let tokens = parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return Set(tokens)
    }

    private var excludedPresentNowIDs: Set<UUID> {
        let names = excludedPresentNowNames
        let ids = students.compactMap { s -> UUID? in
            let name = s.fullName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return names.contains(name) ? s.id : nil
        }
        return Set(ids)
    }

    private var hiddenTestStudentIDs: Set<UUID> {
        guard showTestStudents == false else { return [] }
        let lower = testStudentNamesRaw.lowercased()
        let parts = lower.split(whereSeparator: { ch in ch == "," || ch == ";" || ch.isNewline })
        let tokens = parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let hiddenNames = Set(tokens)
        let ids = students.compactMap { s -> UUID? in
            let name = s.fullName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return hiddenNames.contains(name) ? s.id : nil
        }
        return Set(ids)
    }

    private var presentNowIDs: Set<UUID> {
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        let todays = cachedAttendanceRecords.filter { rec in
            cal.isDate(rec.date, inSameDayAs: today) && (rec.status == .present || rec.status == .tardy)
        }
        // CloudKit compatibility: Convert String studentIDs to UUIDs
        var ids = Set(todays.compactMap { UUID(uuidString: $0.studentID) })
        ids.subtract(hiddenTestStudentIDs)
        ids.subtract(excludedPresentNowIDs)
        return ids
    }
    
    private var presentNowCount: Int { presentNowIDs.count }

    private var daysSinceLastLessonByStudent: [UUID: Int] {
        var result: [UUID: Int] = [:]
        // ... (Existing logic for calculation)
        let excludedLessonIDs: Set<UUID> = {
            func norm(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            let ids = cachedLessons.values.filter { l in
                let s = norm(l.subject)
                let g = norm(l.group)
                return s == "parsha" || g == "parsha"
            }.map { $0.id }
            return Set(ids)
        }()

        let given = cachedStudentLessons.filter { $0.isGiven && !excludedLessonIDs.contains($0.resolvedLessonID) }
        var lastDateByStudent: [UUID: Date] = [:]
        for sl in given {
            let when = sl.givenAt ?? sl.scheduledFor ?? sl.createdAt
            for sid in sl.resolvedStudentIDs {
                if let existing = lastDateByStudent[sid] {
                    if when > existing { lastDateByStudent[sid] = when }
                } else {
                    lastDateByStudent[sid] = when
                }
            }
        }
        for s in students {
            if let last = lastDateByStudent[s.id] {
                let days = LessonAgeHelper.schoolDaysSinceCreation(createdAt: last, asOf: Date(), using: modelContext, calendar: calendar)
                result[s.id] = days
            } else {
                result[s.id] = -1
            }
        }
        return result
    }

    private var filteredStudents: [Student] {
        if sortOrder == .lastLesson {
            let base = viewModel.filteredStudents(
                students: students,
                filter: selectedFilter,
                sortOrder: .alphabetical,
                presentNowIDs: presentNowIDs,
                showTestStudents: showTestStudents,
                testStudentNames: testStudentNamesRaw
            )
            let daysMap = daysSinceLastLessonByStudent
            return base.sorted { lhs, rhs in
                let l = daysMap[lhs.id] ?? -1
                let r = daysMap[rhs.id] ?? -1
                let lNo = l < 0
                let rNo = r < 0
                if lNo != rNo { return lNo && !rNo }
                if l != r { return l > r }
                let nameOrder = lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName)
                if nameOrder == .orderedSame { return lhs.manualOrder < rhs.manualOrder }
                return nameOrder == .orderedAscending
            }
        } else {
            return viewModel.filteredStudents(
                students: students,
                filter: selectedFilter,
                sortOrder: sortOrder,
                presentNowIDs: presentNowIDs,
                showTestStudents: showTestStudents,
                testStudentNames: testStudentNamesRaw
            )
        }
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            // THE UNIFIED SIDEBAR
            unifiedSidebar
                .frame(width: 200)
                .background(Color.gray.opacity(0.08))

            Divider()

            // THE CONTENT SWITCHER
            Group {
                switch mode {
                case .roster:
                    rosterGridContent
                case .attendance:
                    attendanceContent
                case .workOverview:
                    workloadContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Sheets and Alerts
        .sheet(isPresented: $showingAddStudent) {
            AddStudentView()
        }
        .sheet(isPresented: Binding(get: { selectedStudentID != nil }, set: { if !$0 { selectedStudentID = nil } })) {
            if let id = selectedStudentID, let student = students.first(where: { $0.id == id }) {
                StudentDetailView(student: student) {
                    selectedStudentID = nil
                }
            }
        }
        .alert("Save Failed", isPresented: $isShowingSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage)
        }
        .alert(item: $importAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
        // CSV Importer Logic
        .fileImporter(
            isPresented: $showingStudentCSVImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText]
        ) { result in
            handleFileImport(result)
        }
        .sheet(isPresented: $showingMappingSheet) {
            StudentCSVMappingView(headers: mappingHeaders, onCancel: {
                showingMappingSheet = false
                pendingFileURL = nil
            }, onConfirm: { mapping in
                handleMappingConfirm(mapping)
            })
        }
        .sheet(item: $pendingParsedImport, onDismiss: { pendingFileURL = nil }) { parsed in
            StudentImportPreviewView(parsed: parsed, onCancel: {
                pendingParsedImport = nil
            }, onConfirm: { filtered in
                handleImportCommit(filtered)
            })
            .frame(minWidth: 620, minHeight: 520)
        }
        .onChange(of: appRouter.navigationDestination) { _, destination in
            if case .newStudent = destination {
                mode = .roster
                showingAddStudent = true
                appRouter.clearNavigation()
            } else if case .importStudents = destination {
                mode = .roster
                showingStudentCSVImporter = true
                appRouter.clearNavigation()
            } else if case .openStudentDetail(let studentID) = destination {
                mode = .roster
                selectedStudentID = studentID
                appRouter.clearNavigation()
            }
        }
        .onAppear { 
            ensureInitialManualOrderIfNeeded()
            // Load data on-demand based on mode
            Task { @MainActor in
                await loadDataOnDemand()
            }
        }
        .onChange(of: mode) { _, _ in
            Task { @MainActor in
                await loadDataOnDemand()
            }
        }
        .onChange(of: studentsSortOrderRaw) { _, _ in
            Task { @MainActor in
                await loadDataOnDemand()
            }
        }
        .onChange(of: studentsFilterRaw) { _, _ in
            Task { @MainActor in
                await loadDataOnDemand()
            }
        }
        .onChange(of: attendanceRecordIDs) { _, _ in
            Task { @MainActor in
                await loadDataOnDemand()
            }
        }
        .onChange(of: studentLessonIDs) { _, _ in
            Task { @MainActor in
                await loadDataOnDemand()
            }
        }
        .onChange(of: lessonIDs) { _, _ in
            Task { @MainActor in
                await loadDataOnDemand()
            }
        }
        .onChange(of: students.map { $0.id }) { _, _ in
            ensureInitialManualOrderIfNeeded()
            if viewModel.repairManualOrderUniquenessIfNeeded(students) {
                try? modelContext.save()
            }
        }
    }

    // MARK: - Sidebar

    private var unifiedSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                // SECTION 1: NAVIGATION
                VStack(alignment: .leading, spacing: 4) {
                    Text("MODE")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                    
                    SidebarNavButton(title: "Roster", icon: "person.3", isSelected: mode == .roster) {
                        mode = .roster
                    }
                    SidebarNavButton(title: "Attendance", icon: "checklist", isSelected: mode == .attendance) {
                        mode = .attendance
                    }
                    SidebarNavButton(title: "Workload", icon: "doc.text", isSelected: mode == .workOverview) {
                        mode = .workOverview
                    }
                }

                // SECTION 2: ROSTER TOOLS (Only visible in Roster Mode)
                if mode == .roster {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("SORT ORDER")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)

                        SidebarFilterButton(icon: "textformat.abc", title: "A–Z", color: .accentColor, isSelected: sortOrder == .alphabetical) {
                            withAnimation { studentsSortOrderRaw = "alphabetical" }
                        }
                        SidebarFilterButton(icon: "calendar", title: "Age", color: .accentColor, isSelected: sortOrder == .age) {
                            withAnimation { studentsSortOrderRaw = "age" }
                        }
                        SidebarFilterButton(icon: "gift", title: "Birthday", color: .accentColor, isSelected: sortOrder == .birthday) {
                            withAnimation { studentsSortOrderRaw = "birthday" }
                        }
                        SidebarFilterButton(icon: "clock.badge.exclamationmark", title: "Last Lesson", color: .accentColor, isSelected: sortOrder == .lastLesson) {
                            withAnimation { studentsSortOrderRaw = "lastLesson" }
                        }
                        SidebarFilterButton(icon: "arrow.up.arrow.down", title: "Manual", color: .accentColor, isSelected: sortOrder == .manual) {
                            withAnimation { studentsSortOrderRaw = "manual" }
                        }

                        Text("FILTERS")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)

                        SidebarFilterButton(icon: "person.3.fill", title: "All", color: .accentColor, isSelected: selectedFilter == .all) {
                            withAnimation { studentsFilterRaw = "all" }
                        }
                        SidebarFilterButton(
                            icon: "checkmark.circle.fill",
                            title: "Present Now",
                            color: .green,
                            isSelected: selectedFilter == .presentNow,
                            trailingBadgeText: presentNowCount > 0 ? "\(presentNowCount)" : nil,
                            trailingBadgeColor: .green
                        ) {
                            withAnimation { studentsFilterRaw = "presentNow" }
                        }
                        
                        ForEach(levelFilters, id: \.self) { filter in
                            SidebarFilterButton(icon: "circle.fill", title: filter.title, color: filter.color, isSelected: selectedFilter == filter) {
                                withAnimation { selectedFilterRawAssignment(for: filter) }
                            }
                        }
                    }
                    .transition(.opacity)
                }
            }
            .padding(.vertical, 16)
        }
    }

    // MARK: - Roster Content

    private var rosterGridContent: some View {
        Group {
            if filteredStudents.isEmpty {
                VStack(spacing: 8) {
                    Text("No students yet")
                        .font(.system(size: AppTheme.FontSize.titleMedium, weight: .semibold, design: .rounded))
                    Text("Click the plus button to add your first student.")
                        .font(.system(size: AppTheme.FontSize.body, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            } else {
                StudentsCardsGridView(
                    students: filteredStudents,
                    isBirthdayMode: sortOrder == .birthday,
                    isAgeMode: sortOrder == .age,
                    isLastLessonMode: sortOrder == .lastLesson,
                    lastLessonDays: daysSinceLastLessonByStudent,
                    isManualMode: sortOrder == .manual,
                    onTapStudent: { selectedStudentID = $0.id },
                    onReorder: { movingStudent, fromIndex, toIndex, subset in
                        let newAllIDs = viewModel.mergeReorderedSubsetIntoAll(
                            movingID: movingStudent.id,
                            from: fromIndex,
                            to: toIndex,
                            current: subset,
                            allStudents: students
                        )
                        assignManualOrder(from: newAllIDs)
                        try? modelContext.save()
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            Button {
                showingAddStudent = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: AppTheme.FontSize.titleXLarge))
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: [.command])
            .contextMenu {
                Button {
                    showingStudentCSVImporter = true
                } label: {
                    Label("Import Students from CSV…", systemImage: "arrow.down.doc")
                }
            }
            .padding()
        }
        .overlay {
            ParsingOverlay(isParsing: $isParsing) {
                parsingTask?.cancel()
            }
        }
    }

    // MARK: - Logic Helpers
    
    // MARK: - On-Demand Data Loading
    
    /// Loads data on-demand based on current mode and filters
    @MainActor
    private func loadDataOnDemand() async {
        guard mode == .roster else {
            // Clear caches when not in roster mode
            cachedAttendanceRecords = []
            cachedStudentLessons = []
            cachedLessons = [:]
            return
        }
        
        // Load attendanceRecords if needed for presentNow filter or count
        // Always load in roster mode to show "Present Now" count in sidebar
        let needsAttendanceRecords = true
        if needsAttendanceRecords {
            // Fetch only today's attendance records
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? today
            do {
                let descriptor = FetchDescriptor<AttendanceRecord>(
                    predicate: #Predicate { rec in
                        rec.date >= today && rec.date < tomorrow
                    },
                    sortBy: [SortDescriptor(\.date, order: .forward)]
                )
                cachedAttendanceRecords = try modelContext.fetch(descriptor)
            } catch {
                cachedAttendanceRecords = modelContext.safeFetch(FetchDescriptor<AttendanceRecord>())
                    .filter { cal.isDate($0.date, inSameDayAs: today) }
            }
        } else {
            cachedAttendanceRecords = []
        }
        
        // Load studentLessons and lessons only if sortOrder == .lastLesson
        if sortOrder == .lastLesson {
            // Fetch all studentLessons (needed for lastLesson calculation)
            do {
                let descriptor = FetchDescriptor<StudentLesson>(
                    sortBy: [SortDescriptor(\.createdAt, order: .forward)]
                )
                cachedStudentLessons = try modelContext.fetch(descriptor)
            } catch {
                cachedStudentLessons = modelContext.safeFetch(FetchDescriptor<StudentLesson>())
            }
            
            // Fetch lessons referenced by studentLessons
            let neededLessonIDs = Set(cachedStudentLessons.map { $0.resolvedLessonID })
            if !neededLessonIDs.isEmpty {
                do {
                    let descriptor = FetchDescriptor<Lesson>(
                        predicate: #Predicate { neededLessonIDs.contains($0.id) }
                    )
                    let fetched = try modelContext.fetch(descriptor)
                    cachedLessons = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
                } catch {
                    let allLessons = modelContext.safeFetch(FetchDescriptor<Lesson>())
                    cachedLessons = Dictionary(uniqueKeysWithValues: allLessons.filter { neededLessonIDs.contains($0.id) }.map { ($0.id, $0) })
                }
            } else {
                cachedLessons = [:]
            }
        } else {
            cachedStudentLessons = []
            cachedLessons = [:]
        }
    }

    private func ensureInitialManualOrderIfNeeded() {
        if viewModel.ensureInitialManualOrderIfNeeded(students) {
            try? modelContext.save()
        }
    }
    
    private func assignManualOrder(from orderedIDs: [UUID]) {
        for (idx, id) in orderedIDs.enumerated() {
            if let s = students.first(where: { $0.id == id }) {
                s.manualOrder = idx
            }
        }
    }
    
    private func selectedFilterRawAssignment(for filter: StudentsFilter) {
        switch filter {
        case .upper: studentsFilterRaw = "upper"
        case .lower: studentsFilterRaw = "lower"
        case .presentNow: studentsFilterRaw = "presentNow"
        case .all: studentsFilterRaw = "all"
        }
    }

    // MARK: - CSV Handlers

    private func handleFileImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            parsingTask?.cancel()
            isParsing = true
            parsingTask = StudentsImportCoordinator.startHeaderScan(from: url, onParsed: { headers, mapping in
                self.pendingFileURL = url
                self.mappingHeaders = headers
                self.pendingMapping = mapping
                self.showingMappingSheet = true
            }, onError: { error in
                self.importAlert = ImportAlert(title: "Import Failed", message: error.localizedDescription)
            }, onFinally: {
                self.isParsing = false
                self.parsingTask = nil
            })
        } catch {
            importAlert = ImportAlert(title: "Import Failed", message: error.localizedDescription)
            isParsing = false
            parsingTask = nil
        }
    }

    private func handleMappingConfirm(_ mapping: StudentCSVImporter.Mapping) {
        guard let fileURL = pendingFileURL else { return }
        parsingTask?.cancel()
        isParsing = true
        parsingTask = StudentsImportCoordinator.startMappedParse(from: fileURL, mapping: mapping, students: self.students, onParsed: { parsed in
            self.pendingParsedImport = parsed
            self.showingMappingSheet = false
        }, onError: { error in
            self.importAlert = ImportAlert(title: "Import Failed", message: error.localizedDescription)
            self.showingMappingSheet = false
        }, onFinally: {
            self.isParsing = false
            self.parsingTask = nil
        })
    }

    private func handleImportCommit(_ filtered: StudentCSVImporter.Parsed) {
        do {
            let result = try ImportCommitService.commitStudents(parsed: filtered, into: modelContext, existingStudents: students)
            importAlert = ImportAlert(title: result.title, message: result.message)
        } catch {
            importAlert = ImportAlert(title: "Import Failed", message: error.localizedDescription)
        }
        pendingParsedImport = nil
    }
}

// MARK: - Sidebar Button Helper
struct SidebarNavButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 20)
                Text(title)
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }
}
