// WorksAgendaView.swift
// Split view combining open-work grid with a planning calendar pane.
//
// Helpers live in:
// - WorksAgendaView+DataHelpers.swift  (cache loading, filtering, display helpers)
// - WorksAgendaView+Actions.swift      (calendar navigation, work item actions)

import OSLog
import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
import PDFKit
#endif

struct WorksAgendaView: View {
    static let logger = Logger.work

    @Environment(\.modelContext) var modelContext
    @Environment(\.calendar) var calendar
    @Environment(SaveCoordinator.self) var saveCoordinator
    @Environment(RestoreCoordinator.self) private var restoreCoordinator

    @Query(
        filter: #Predicate<WorkModel> { $0.statusRaw != "complete" },
        sort: [SortDescriptor(\WorkModel.createdAt, order: .reverse)]
    )
    var openWork: [WorkModel]

    @Query(
        filter: #Predicate<WorkCheckIn> { $0.statusRaw == "Scheduled" },
        sort: [SortDescriptor(\WorkCheckIn.date)]
    )
    var scheduledCheckIns: [WorkCheckIn]

    // MEMORY OPTIMIZATION: Use lightweight queries for change detection only (IDs only)
    // Extract IDs immediately to avoid retaining full objects - significantly reduces memory usage
    @Query(sort: [SortDescriptor(\Lesson.id)]) private var lessonsForChangeDetection: [Lesson]
    @Query(sort: [SortDescriptor(\Student.id)]) private var studentsForChangeDetection: [Student]

    // MEMORY OPTIMIZATION: Extract only IDs for change detection to avoid loading full objects
    private var lessonIDs: [UUID] { lessonsForChangeDetection.map { $0.id } }
    private var studentIDs: [UUID] { studentsForChangeDetection.map { $0.id } }

    // Lazy-loaded caches (only populated when needed)
    @State var lessonsByIDCache: [UUID: Lesson] = [:]
    @State var studentsByIDCache: [UUID: Student] = [:]

    @AppStorage(UserDefaultsKeys.generalShowTestStudents) var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames)
    var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"
    @AppStorage(UserDefaultsKeys.workAgendaHideScheduled) var hideScheduled: Bool = false

    @State var sortMode: WorkAgendaSortMode = .lesson
    @State var searchText: String = ""
    @State var debouncedSearchText: String = ""
    @State var searchDebounceTask: Task<Void, Never>?
    @State var calendarHeightRatio: CGFloat = 0.5 // 50% calendar, 50% open work
    @State var isCalendarMinimized: Bool = false
    @State var calendarStartDate: Date = AppCalendar.startOfDay(Date())

    @State var selected: SelectionToken?

    struct SelectionToken: Identifiable, Equatable { let id: UUID; let workID: UUID }

    // MEMORY OPTIMIZATION: Load lessons and students on-demand based on contracts
    var lessonsByID: [UUID: Lesson] { lessonsByIDCache }
    var studentsByID: [UUID: Student] { studentsByIDCache }

    /// Combined trigger for data reload — changes when any relevant data changes
    private var dataReloadTrigger: Int {
        var hasher = Hasher()
        hasher.combine(openWork.map { $0.id })
        hasher.combine(lessonIDs)
        hasher.combine(studentIDs)
        hasher.combine(showTestStudents)
        hasher.combine(testStudentNamesRaw)
        return hasher.finalize()
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
                .sheet(item: $selected, onDismiss: { selected = nil }, content: { token in
                    let id = token.workID
                    let fetch = FetchDescriptor<WorkModel>(predicate: #Predicate { $0.id == id })
                    if let w = modelContext.safeFetchFirst(fetch) {
                        WorkDetailView(workID: w.id)
                            .id(token.id)
                    } else {
                        ContentUnavailableView("Work not found", systemImage: "exclamationmark.triangle")
                    }
                })
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
