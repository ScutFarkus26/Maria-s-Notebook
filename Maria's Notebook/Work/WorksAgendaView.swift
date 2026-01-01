import SwiftUI
import SwiftData

struct WorksAgendaView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @EnvironmentObject private var saveCoordinator: SaveCoordinator
    @EnvironmentObject private var restoreCoordinator: RestoreCoordinator

    // MEMORY OPTIMIZATION: Only load active/review contracts (open work), not all contracts
    @Query(filter: #Predicate<WorkContract> { $0.statusRaw == "active" || $0.statusRaw == "review" }) 
    private var openContracts: [WorkContract]
    
    // MEMORY OPTIMIZATION: Use lightweight queries for change detection only
    // The actual data is loaded on-demand when needed
    @Query private var lessonIDs: [Lesson]
    @Query private var studentIDs: [Student]
    
    // Lazy-loaded caches (only populated when needed)
    @State private var lessonsByIDCache: [UUID: Lesson] = [:]
    @State private var studentsByIDCache: [UUID: Student] = [:]

    @AppStorage("General.showTestStudents") private var showTestStudents: Bool = false
    @AppStorage("General.testStudentNames") private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    @State private var sortMode: WorkAgendaSortMode = .lesson
    @State private var searchText: String = ""
    @State private var calendarHeightRatio: CGFloat = 0.5 // 50% calendar, 50% open work

    @State private var selectedContractID: UUID? = nil

    private struct SelectionToken: Identifiable, Equatable { let id: UUID; let contractID: UUID }
    @State private var selected: SelectionToken? = nil

    // MEMORY OPTIMIZATION: Load lessons and students on-demand based on contracts
    private var lessonsByID: [UUID: Lesson] { lessonsByIDCache }
    private var studentsByID: [UUID: Student] { studentsByIDCache }
    
    private func loadLessonsAndStudentsIfNeeded() {
        // Collect IDs from open contracts
        var neededLessonIDs = Set<UUID>()
        var neededStudentIDs = Set<UUID>()
        
        for contract in openContracts {
            if let lid = UUID(uuidString: contract.lessonID) {
                neededLessonIDs.insert(lid)
            }
            if let sid = UUID(uuidString: contract.studentID) {
                neededStudentIDs.insert(sid)
            }
        }
        
        // Load only needed lessons
        if !neededLessonIDs.isEmpty {
            do {
                let descriptor = FetchDescriptor<Lesson>(
                    predicate: #Predicate { neededLessonIDs.contains($0.id) }
                )
                let fetched = try modelContext.fetch(descriptor)
                lessonsByIDCache = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
            } catch {
                // Fallback: load all if predicate fails
                let all = (try? modelContext.fetch(FetchDescriptor<Lesson>())) ?? []
                lessonsByIDCache = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
            }
        } else {
            lessonsByIDCache = [:]
        }
        
        // Load only needed students
        if !neededStudentIDs.isEmpty {
            do {
                let descriptor = FetchDescriptor<Student>(
                    predicate: #Predicate { neededStudentIDs.contains($0.id) }
                )
                let fetched = try modelContext.fetch(descriptor)
                let visible = TestStudentsFilter.filterVisible(fetched, show: showTestStudents, namesRaw: testStudentNamesRaw)
                studentsByIDCache = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0) })
            } catch {
                // Fallback: load all if predicate fails
                let all = (try? modelContext.fetch(FetchDescriptor<Student>())) ?? []
                let visible = TestStudentsFilter.filterVisible(all, show: showTestStudents, namesRaw: testStudentNamesRaw)
                studentsByIDCache = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0) })
            }
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
                        // Top ~68%: Open Work grid
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
                        .frame(height: geo.size.height * (1 - calendarHeightRatio))

                        Divider()

                        // Bottom ~32%: Calendar pane
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Planning Calendar").font(.title3.weight(.semibold))
                                Spacer()
                                Button("Today") { /* optional hook if needed */ }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            WorkAgendaCalendarPane(startDate: Date(), daysCount: 10)
                                .frame(maxHeight: .infinity)
                        }
                        .frame(height: geo.size.height * calendarHeightRatio)
                    }
                }
                .navigationTitle("Work Agenda")
                .sheet(item: $selected, onDismiss: { selected = nil }) { token in
                    let id = token.contractID
                    let fetch = FetchDescriptor<WorkContract>(predicate: #Predicate { $0.id == id })
                    if let c = try? modelContext.fetch(fetch).first {
                        WorkContractDetailSheet(contract: c) { selected = nil }
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
        .onChange(of: openContracts.map { $0.id }) { _, _ in
            // Reload when contracts change
            loadLessonsAndStudentsIfNeeded()
        }
        .onChange(of: lessonIDs.map { $0.id }) { _, _ in
            loadLessonsAndStudentsIfNeeded()
        }
        .onChange(of: studentIDs.map { $0.id }) { _, _ in
            loadLessonsAndStudentsIfNeeded()
        }
        .onChange(of: showTestStudents) { _, _ in
            loadLessonsAndStudentsIfNeeded()
        }
        .onChange(of: testStudentNamesRaw) { _, _ in
            loadLessonsAndStudentsIfNeeded()
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text("Open Work").font(.title3.weight(.semibold))
                Spacer()
                Picker("Sort", selection: $sortMode) {
                    ForEach(WorkAgendaSortMode.allCases) { m in Text(m.rawValue).tag(m) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search students or lessons", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Data helpers
    private func openWorksFiltered() -> [WorkContract] {
        // openContracts already contains only active/review contracts (open work)
        var works = openContracts
        works = works.filter { c in
            if let sid = UUID(uuidString: c.studentID) { return studentsByID[sid] != nil }
            return false
        }
        // Optional search
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let query = searchText.lowercased()
            works = works.filter { c in
                var hay: [String] = []
                hay.append(lessonTitle(forLessonID: c.lessonID))
                if let sid = UUID(uuidString: c.studentID), let s = studentsByID[sid] {
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
            let name = lesson.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        return "Lesson \(String(lessonID.prefix(6)))"
    }

    // MARK: - Actions
    private func openDetail(_ c: WorkContract) {
        selected = nil
        let token = SelectionToken(id: UUID(), contractID: c.id)
        DispatchQueue.main.async { selected = token }
    }

    private func markCompleted(_ c: WorkContract) {
        c.status = .complete
        _ = saveCoordinator.save(modelContext, reason: "Mark work completed")
    }

    private func scheduleToday(_ c: WorkContract) {
        let today = AppCalendar.startOfDay(Date())
        // Update or create a single plan item for this contract
        let workID: UUID = c.id
        let fetch = FetchDescriptor<WorkPlanItem>(predicate: #Predicate<WorkPlanItem> { $0.workID == workID })
        let existing = (try? modelContext.fetch(fetch)) ?? []
        if let first = existing.sorted(by: { $0.scheduledDate < $1.scheduledDate }).first {
            first.scheduledDate = today
        } else {
            let item = WorkPlanItem(workID: c.id, scheduledDate: today, reason: .progressCheck, note: nil)
            modelContext.insert(item)
        }
        c.scheduledDate = today
        _ = saveCoordinator.save(modelContext, reason: "Quick schedule today")
    }
}

#Preview {
    // Encapsulate data setup in a closure to avoid Void return statements in ViewBuilder
    let container: ModelContainer = {
        let schema = AppSchema.schema
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: configuration)
        let ctx = container.mainContext
        
        let s = Student(firstName: "Ada", lastName: "Lovelace", birthday: Date(), level: .upper)
        let l = Lesson(name: "Long Division", subject: "Math", group: "Ops", subheading: "", writeUp: "")
        ctx.insert(s)
        ctx.insert(l)
        let c = WorkContract(studentID: s.id.uuidString, lessonID: l.id.uuidString, presentationID: nil, status: .active)
        ctx.insert(c)
        return container
    }()

    WorksAgendaView()
        .previewEnvironment(using: container)
        .environmentObject(SaveCoordinator.preview)
}
