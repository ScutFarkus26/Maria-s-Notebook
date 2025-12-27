import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct StudentsRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var students: [Student]
    @Query(sort: \StudentLesson.createdAt, order: .forward) private var studentLessons: [StudentLesson]
    @Query(sort: \Lesson.name, order: .forward) private var lessons: [Lesson]
    @Query(sort: \WorkModel.createdAt, order: .reverse) private var workItems: [WorkModel]

    @State private var showingAddStudent: Bool = false
    @State private var showingStudentCSVImporter: Bool = false
    @State private var importAlert: ImportAlert? = nil

    @State private var mappingHeaders: [String] = []
    @State private var pendingMapping: StudentCSVImporter.Mapping? = nil
    @State private var pendingFileURL: URL? = nil
    @State private var pendingParsedImport: StudentCSVImporter.Parsed? = nil
    @State private var showingMappingSheet: Bool = false

    @State private var isParsing: Bool = false
    @State private var parsingTask: Task<Void, Never>? = nil

    @State private var selectedStudentID: UUID? = nil
    @State private var selectedWorkID: UUID? = nil

    private struct ImportAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private enum Mode: String, CaseIterable, Identifiable { 
        case roster = "Roster"
        case attendance = "Attendance"
        case workOverview = "Overview"
        var id: String { rawValue }
    }
    
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @AppStorage("StudentsRootView.mode") private var modeRaw: String = Mode.roster.rawValue
    private var mode: Mode { Mode(rawValue: modeRaw) ?? .roster }

    var body: some View {
        VStack(spacing: 0) {
            // Top pill navigation (Roster / Attendance / Overview)
            #if os(iOS)
            Group {
                if horizontalSizeClass == .compact {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            Spacer(minLength: 0)
                            HStack(spacing: 12) {
                                PillButton(title: Mode.attendance.rawValue, isSelected: mode == .attendance) { modeRaw = Mode.attendance.rawValue }
                                PillButton(title: Mode.roster.rawValue, isSelected: mode == .roster) { modeRaw = Mode.roster.rawValue }
                                PillButton(title: Mode.workOverview.rawValue, isSelected: mode == .workOverview) { modeRaw = Mode.workOverview.rawValue }
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                } else {
                    HStack {
                        Spacer()
                        HStack(spacing: 12) {
                            PillButton(title: Mode.attendance.rawValue, isSelected: mode == .attendance) { modeRaw = Mode.attendance.rawValue }
                            PillButton(title: Mode.roster.rawValue, isSelected: mode == .roster) { modeRaw = Mode.roster.rawValue }
                            PillButton(title: Mode.workOverview.rawValue, isSelected: mode == .workOverview) { modeRaw = Mode.workOverview.rawValue }
                        }
                        Spacer()
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                }
            }
            #else
            HStack {
                Spacer()
                HStack(spacing: 12) {
                    PillButton(title: Mode.attendance.rawValue, isSelected: mode == .attendance) { modeRaw = Mode.attendance.rawValue }
                    PillButton(title: Mode.roster.rawValue, isSelected: mode == .roster) { modeRaw = Mode.roster.rawValue }
                    PillButton(title: Mode.workOverview.rawValue, isSelected: mode == .workOverview) { modeRaw = Mode.workOverview.rawValue }
                }
                Spacer()
            }
            .padding(.top, 8)
            .padding(.bottom, 8)
            #endif

            Divider()

            Group {
                if mode == .roster {
                    rosterContent
                } else if mode == .attendance {
                    AttendanceView()
                } else {
                    workOverviewContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: Binding(get: { selectedStudentID != nil }, set: { if !$0 { selectedStudentID = nil } })) {
            if let id = selectedStudentID, let student = students.first(where: { $0.id == id }) {
                StudentDetailView(student: student) {
                    selectedStudentID = nil
                }
            } else {
                EmptyView()
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
        // Allow external triggers to jump straight to Attendance mode
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenAttendanceRequested"))) { _ in
            modeRaw = Mode.attendance.rawValue
        }
    }

    private var rosterContent: some View {
        StudentsView()
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

                Button("") { showingStudentCSVImporter = true }
                    .keyboardShortcut("I", modifiers: [.command, .shift])
                    .opacity(0.001)
                    .accessibilityHidden(true)
            }
            .overlay {
                ParsingOverlay(isParsing: $isParsing) {
                    parsingTask?.cancel()
                }
            }
            .sheet(isPresented: $showingAddStudent) {
                AddStudentView()
            }
            .fileImporter(
                isPresented: $showingStudentCSVImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText]
            ) { result in
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
            .sheet(isPresented: $showingMappingSheet) {
                StudentCSVMappingView(headers: mappingHeaders, onCancel: {
                    showingMappingSheet = false
                    pendingFileURL = nil
                }, onConfirm: { mapping in
                    // Ensure we have a file URL before starting the background work
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
                })
            }
            .sheet(item: $pendingParsedImport, onDismiss: {
                pendingFileURL = nil
            }) { parsed in
                StudentImportPreviewView(parsed: parsed, onCancel: {
                    pendingParsedImport = nil
                }, onConfirm: { filtered in
                    do {
                        let result = try ImportCommitService.commitStudents(parsed: filtered, into: modelContext, existingStudents: students)
                        importAlert = ImportAlert(title: result.title, message: result.message)
                    } catch {
                        importAlert = ImportAlert(title: "Import Failed", message: error.localizedDescription)
                    }
                    pendingParsedImport = nil
                })
                .frame(minWidth: 620, minHeight: 520)
            }
            .alert(item: $importAlert) { alert in
                Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NewStudentRequested"))) { _ in
                showingAddStudent = true
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ImportStudentsRequested"))) { _ in
                showingStudentCSVImporter = true
            }
    }

    private var workOverviewContent: some View {
        // Build lookup service and derived data to reuse WorkStudentsGrid
        let lookupService = WorkLookupService(
            students: students,
            lessons: lessons,
            studentLessons: studentLessons
        )
        let openWorks: [WorkModel] = workItems.filter { $0.isOpen }
        var openByStudent: [UUID: [WorkModel]] = [:]
        for work in openWorks {
            for p in (work.participants ?? []) {
                openByStudent[p.studentID, default: []].append(work)
            }
        }
        var counts: [UUID: (practice: Int, follow: Int, research: Int)] = [:]
        for work in openWorks {
            for p in (work.participants ?? []) {
                switch work.workType {
                case .practice: counts[p.studentID, default: (0,0,0)].practice += 1
                case .followUp: counts[p.studentID, default: (0,0,0)].follow += 1
                case .research: counts[p.studentID, default: (0,0,0)].research += 1
                }
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
            openWorksByStudentID: openByStudent,
            lookupService: lookupService,
            onTapStudent: { student in selectedStudentID = student.id },
            onTapWork: { work in selectedWorkID = work.id }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

