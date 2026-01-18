import SwiftUI
import SwiftData

struct FollowUpInboxView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appRouter) private var appRouter

    // Step 2 — Local rule constants (no settings yet)
    private let lessonFollowUpOverdueDays: Int = 7
    private let workStaleOverdueDays: Int = 5
    private let reviewStaleDays: Int = 3

    // Loaded data (replaces unfiltered @Query)
    @State private var inboxData: InboxData?
    
    // Lightweight change detection queries (IDs only to detect when to reload)
    @Query(sort: [SortDescriptor(\StudentLesson.id)]) private var studentLessonsForChangeDetection: [StudentLesson]
    // ENERGY OPTIMIZATION: Filter WorkModel change detection to only non-complete items that can affect the follow-up inbox.
    // This matches FollowUpInboxEngine's filter (statusRaw != "complete") and significantly reduces memory usage
    // by avoiding monitoring of completed work that cannot appear in the inbox.
    @Query(
        filter: #Predicate<WorkModel> { work in
            work.statusRaw != "complete"
        },
        sort: [SortDescriptor(\WorkModel.id)]
    ) private var workModelsForChangeDetection: [WorkModel]
    
    // Query Notes with work relationship (migrated WorkNote objects)
    // Filter in memory for those with "[TO GIVE] " prefix (migrated from WorkNote.isLessonToGive)
    @Query(
        filter: #Predicate<Note> { $0.work != nil },
        sort: [SortDescriptor(\Note.createdAt, order: .reverse)]
    ) private var allWorkNotes: [Note]
    
    private var lessonReminderNotes: [Note] {
        allWorkNotes.filter { note in
            note.body.hasPrefix("[TO GIVE] ")
        }
    }
    
    // Extract IDs for change detection
    private var studentLessonIDs: [UUID] {
        studentLessonsForChangeDetection.map { $0.id }
    }
    private var workModelIDs: [UUID] {
        workModelsForChangeDetection.map { $0.id }
    }

    @AppStorage("General.showTestStudents") private var showTestStudents: Bool = false
    @AppStorage("General.testStudentNames") private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    private var visibleStudents: [Student] {
        guard let data = inboxData else { return [] }
        return TestStudentsFilter.filterVisible(data.students, show: showTestStudents, namesRaw: testStudentNamesRaw)
    }
    
    // Computed properties for data access
    // Engine fetches WorkModel data internally, so contracts/planItems/notes are not needed
    private var lessons: [Lesson] { inboxData?.lessons ?? [] }
    private var students: [Student] { inboxData?.students ?? [] }
    private var studentLessons: [StudentLesson] { inboxData?.studentLessons ?? [] }
    
    private func loadData() async {
        // Yield to allow the view to appear immediately before the heavy fetch
        await Task.yield()
        
        // Minimal data loading - engine handles WorkModel fetching internally
        // Still need students, lessons, and studentLessons for display
        let loader = InboxDataLoader(context: modelContext)
        let data = loader.loadInboxData()
        // Create minimal InboxData with only what we need
        inboxData = InboxData(
            studentLessons: data.studentLessons,
            planItems: [], // Not used - engine fetches WorkModel internally
            notes: [], // Not used - engine fetches WorkModel internally
            students: data.students,
            lessons: data.lessons
        )
        
    }

    // Simple filter control
    private enum Filter: String, CaseIterable, Identifiable { case all = "All", overdue = "Overdue", today = "Due Today"; var id: String { rawValue } }
    @State private var filter: Filter = .all

    // Sheet selections
    private struct SLToken: Identifiable { let id: UUID }
    private struct ContractToken: Identifiable { let id: UUID }
    private struct WorkToken: Identifiable { let id: UUID }
    @State private var selectedSL: SLToken? = nil
    @State private var selectedContract: ContractToken? = nil
    @State private var selectedWork: WorkToken? = nil

    private var items: [FollowUpInboxItem] {
        let constants = FollowUpInboxEngine.Constants(
            lessonFollowUpOverdueDays: lessonFollowUpOverdueDays,
            workStaleOverdueDays: workStaleOverdueDays,
            reviewStaleDays: reviewStaleDays
        )
        return FollowUpInboxEngine.computeItems(
            lessons: lessons,
            students: visibleStudents,
            studentLessons: studentLessons,
            modelContext: modelContext,
            constants: constants
        )
    }

    private var itemsFiltered: [FollowUpInboxItem] {
        switch filter {
        case .all: return items
        case .overdue: return ArrayFiltering.filterByEnum(items: items, value: FollowUpInboxItem.Bucket.overdue, extractor: { $0.bucket })
        case .today: return ArrayFiltering.filterByEnum(items: items, value: FollowUpInboxItem.Bucket.dueToday, extractor: { $0.bucket })
        }
    }

    private var overdue: [FollowUpInboxItem] { itemsFiltered.filter { $0.bucket == .overdue } }
    private var dueToday: [FollowUpInboxItem] { itemsFiltered.filter { $0.bucket == .dueToday } }
    private var upcoming: [FollowUpInboxItem] { itemsFiltered.filter { $0.bucket == .upcoming } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if overdue.isEmpty && dueToday.isEmpty && upcoming.isEmpty && lessonReminderNotes.isEmpty {
                ContentUnavailableView("Nothing due", systemImage: "tray", description: Text("You're all caught up."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !lessonReminderNotes.isEmpty {
                        Section("Lessons to Give") {
                            ForEach(lessonReminderNotes, id: \.id) { note in
                                lessonReminderRow(note)
                            }
                        }
                    }
                    if !overdue.isEmpty {
                        Section("Overdue") {
                            ForEach(overdue, id: \.id) { item in
                                row(item)
                            }
                        }
                    }
                    if !dueToday.isEmpty {
                        Section("Due Today") {
                            ForEach(dueToday, id: \.id) { item in
                                row(item)
                            }
                        }
                    }
                    if !upcoming.isEmpty {
                        Section("Upcoming") {
                            ForEach(upcoming, id: \.id) { item in
                                row(item)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(16)
        .task {
            await loadData()
        }
        .onChange(of: studentLessonIDs) { _, _ in
            Task { await loadData() }
        }
        .onChange(of: workModelIDs) { _, _ in
            Task { await loadData() }
        }
        .sheet(item: $selectedSL) { token in
            let targetID = token.id
            let fetch = FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.id == targetID })
            if let sl = try? modelContext.fetch(fetch).first {
                StudentLessonDetailView(studentLesson: sl) { selectedSL = nil }
            } else {
                ContentUnavailableView("Lesson not found", systemImage: "exclamationmark.triangle")
            }
        }
        .sheet(item: $selectedContract) { token in
            // Try to find WorkModel by id first (if already migrated)
            let targetID = token.id
            let workModelFetch = FetchDescriptor<WorkModel>(predicate: #Predicate { $0.id == targetID })
            if let workModel = try? modelContext.fetch(workModelFetch).first {
                WorkDetailContainerView(workID: workModel.id) {
                    selectedContract = nil
                }
            } else {
                // Fallback: try to find WorkModel by legacyContractID (if not yet migrated)
                let legacyFetch = FetchDescriptor<WorkModel>(predicate: #Predicate { $0.legacyContractID == targetID })
                if let workModel = try? modelContext.fetch(legacyFetch).first {
                    WorkDetailContainerView(workID: workModel.id) {
                        selectedContract = nil
                    }
                } else {
                    ContentUnavailableView("Work not found", systemImage: "exclamationmark.triangle")
                }
            }
        }
        .sheet(item: $selectedWork) { token in
            WorkDetailContainerView(workID: token.id) {
                selectedWork = nil
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray")
                .imageScale(.large)
                .foregroundStyle(.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Follow-Up Inbox").font(.title3.weight(.semibold))
                Text("Overdue and due-today follow-ups for lessons and work.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Filter", selection: $filter) {
                ForEach(Filter.allCases) { f in Text(f.rawValue).tag(f) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)
        }
        .padding(.horizontal, 4)
    }

    private func studentName(for note: Note) -> String {
        // Extract student from note scope if available
        if case .student(let studentID) = note.scope,
           let s = students.first(where: { $0.id == studentID }) {
            return StudentFormatter.displayName(for: s)
        }
        // Fallback: Get student from work participants
        if let sidString = (note.work?.participants ?? []).first?.studentID,
           let sid = UUID(uuidString: sidString),
           let s = students.first(where: { $0.id == sid }) {
            return StudentFormatter.displayName(for: s)
        }
        return "Unknown student"
    }

    private func workTitle(for note: Note) -> String? {
        guard let w = note.work else { return nil }
        let trimmed = w.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        // Fallback to lesson name if available through StudentLesson
        if let slID = w.studentLessonID,
           let sl = studentLessons.first(where: { $0.id == slID }),
           // CloudKit compatibility: Convert String lessonID to UUID for comparison
           let lessonIDUUID = UUID(uuidString: sl.lessonID),
           let lesson = lessons.first(where: { $0.id == lessonIDUUID }) {
            return lesson.name
        }
        return nil
    }
    
    private func noteBodyWithoutPrefix(_ note: Note) -> String {
        if note.body.hasPrefix("[TO GIVE] ") {
            return String(note.body.dropFirst("[TO GIVE] ".count))
        }
        return note.body
    }

    @ViewBuilder
    private func lessonReminderRow(_ note: Note) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(studentName(for: note))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let wt = workTitle(for: note) {
                        Text("from: \(wt)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(noteBodyWithoutPrefix(note))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Text(note.createdAt, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let w = note.work {
                selectedWork = WorkToken(id: w.id)
            } else if case .student(let studentID) = note.scope {
                appRouter.requestOpenStudentDetail(studentID)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Clear") {
                // Remove "[TO GIVE] " prefix to clear the reminder
                if note.body.hasPrefix("[TO GIVE] ") {
                    note.body = String(note.body.dropFirst("[TO GIVE] ".count))
                }
                try? modelContext.save()
            }.tint(.blue)
        }
    }

    @ViewBuilder
    private func row(_ item: FollowUpInboxItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            // Kind tag
            HStack(spacing: 6) {
                Image(systemName: item.kind.icon)
                Text(item.kind.label)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(item.kind.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(item.kind.tint.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if !item.childName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(item.childName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    Text(item.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(item.statusText)
                    .font(.caption)
                    .foregroundStyle(item.bucket == .overdue ? .red : .secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { open(item) }
    }

    private func open(_ item: FollowUpInboxItem) {
        switch item.kind {
        case .lessonFollowUp:
            selectedSL = SLToken(id: item.underlyingID)
        case .workCheckIn, .workReview:
            selectedWork = WorkToken(id: item.underlyingID)
        }
    }
}

#Preview {
    FollowUpInboxView()
}
/*
Sanity checklist:
 • Add note works
 • Lesson to give appears in Planning
 • Clear removes from Planning but keeps note attached to work
 • Delete note works and cascades appropriately
*/

