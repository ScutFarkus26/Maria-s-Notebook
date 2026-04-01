// WorksAgendaView.swift
// Split view combining open-work grid with a planning calendar pane.
//
// Helpers live in:
// - WorksAgendaView+DataHelpers.swift  (cache loading, filtering, display helpers)
// - WorksAgendaView+Actions.swift      (calendar navigation, work item actions)

import CoreData
import OSLog
import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
import PDFKit
#endif

struct WorksAgendaView: View {
    static let logger = Logger.work

    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.calendar) var calendar
    @Environment(SaveCoordinator.self) var saveCoordinator
    @Environment(RestoreCoordinator.self) private var restoreCoordinator

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDWorkModel.createdAt, ascending: false)],
        predicate: NSPredicate(format: "statusRaw != %@", "complete")
    )
    var openWork: FetchedResults<CDWorkModel>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDWorkCheckIn.date, ascending: true)],
        predicate: NSPredicate(format: "statusRaw == %@", "Scheduled")
    )
    var scheduledCheckIns: FetchedResults<CDWorkCheckIn>

    // PERF: Use lightweight count-based change detection instead of loading full tables.
    @State var lessonChangeToken: Int = 0
    @State var studentChangeToken: Int = 0

    // Lazy-loaded caches (only populated when needed)
    @State var lessonsByIDCache: [UUID: CDLesson] = [:]
    @State var studentsByIDCache: [UUID: CDStudent] = [:]

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
    var lessonsByID: [UUID: CDLesson] { lessonsByIDCache }
    var studentsByID: [UUID: CDStudent] { studentsByIDCache }

    /// Combined trigger for data reload — changes when any relevant data changes
    private var dataReloadTrigger: Int {
        var hasher = Hasher()
        hasher.combine(openWork.count)
        hasher.combine(lessonChangeToken)
        hasher.combine(studentChangeToken)
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
                                    .background(Color.primary.opacity(UIConstants.OpacityConstants.subtle), in: Capsule())
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
                    sheetContent(for: token)
                }
            }
        }
        .onAppear {
            refreshChangeTokens()
            loadLessonsAndStudentsIfNeeded()
        }
        .onChange(of: dataReloadTrigger) { _, _ in
            loadLessonsAndStudentsIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) { _ in
            refreshChangeTokens()
        }
    }

    @ViewBuilder
    private func sheetContent(for token: SelectionToken) -> some View {
        let work = fetchWork(id: token.workID)
        if let w = work {
            WorkDetailView(workID: w.id ?? UUID())
                .id(token.id)
        } else {
            ContentUnavailableView("Work not found", systemImage: "exclamationmark.triangle")
        }
    }

    private func fetchWork(id: UUID) -> CDWorkModel? {
        let request: NSFetchRequest<CDWorkModel> = NSFetchRequest(entityName: "WorkModel")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return viewContext.safeFetch(request).first
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
                            .background(Color.primary.opacity(UIConstants.OpacityConstants.light))
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
            .background(Color.primary.opacity(UIConstants.OpacityConstants.trace))
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
    let stack = CoreDataStack.preview
    let ctx = stack.viewContext

    let s = CDStudent(context: ctx)
    s.firstName = "Ada"; s.lastName = "Lovelace"; s.birthday = Date(); s.level = .upper
    let l = CDLesson(context: ctx)
    l.name = "Long Division"; l.subject = "Math"; l.group = "Ops"
    let w = CDWorkModel(context: ctx)
    w.status = .active; w.studentID = s.id?.uuidString ?? ""; w.lessonID = l.id?.uuidString ?? ""

    return WorksAgendaView()
        .previewEnvironment(using: stack)
        .environment(SaveCoordinator.preview)
}
