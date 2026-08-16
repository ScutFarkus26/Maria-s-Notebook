import SwiftUI
import CoreData

struct WorksLogView: View {
    var embeddedSearchText: String? = nil
    var completedOnly: Bool = false
    var isEmbedded: Bool = false
    var focusedWorkID: UUID? = nil

    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    // Test student filtering
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames)
    private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    @FetchRequest(fetchRequest: {
        let request = NSFetchRequest<CDWorkModel>(entityName: "WorkModel")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDWorkModel.createdAt, ascending: false)]
        request.fetchBatchSize = 50
        // Prefetch unifiedNotes so latestUnifiedNoteText doesn't fault the relationship
        // per row (N+1) when filtering/searching the works list.
        request.relationshipKeyPathsForPrefetching = ["unifiedNotes"]
        return request
    }())
    private var allWorks: FetchedResults<CDWorkModel>

    @FetchRequest(sortDescriptors: []) private var lessons: FetchedResults<CDLesson>
    @FetchRequest(sortDescriptors: []) private var lessonAssignments: FetchedResults<CDLessonAssignment>
    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(keyPath: \CDStudent.firstName, ascending: true),
        NSSortDescriptor(keyPath: \CDStudent.lastName, ascending: true)
    ])
    private var studentsRaw: FetchedResults<CDStudent>
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Filter out test students when setting is disabled.
    // All students, not enrolled-only: this log spans all time, so former
    // students' work history must keep resolving.
    private var students: [CDStudent] {
        TestStudentsFilter.filterVisible(
            Array(studentsRaw).uniqueByID,
            show: showTestStudents,
            namesRaw: testStudentNamesRaw
        )
    }

    @State private var selectedWork: CDWorkModel?

    // Filter state
    @State private var selectedKind: WorkKind?
    @State private var selectedStatuses: Set<WorkStatus> = []
    @State private var selectedStudentIDs: Set<UUID> = []
    @State private var searchText: String = ""

    private var effectiveSearchText: String {
        embeddedSearchText ?? searchText
    }

    // Pagination state
    @State private var pagination = PaginationState(pageSize: 50)

    private struct FocusRevealKey: Hashable {
        let id: UUID?
        let filteredIndex: Int?
    }

    private var lessonsByID: [UUID: CDLesson] {
        // Use uniquingKeysWith to handle CloudKit sync duplicates
        Dictionary(lessons.compactMap { l in l.id.map { ($0, l) } }, uniquingKeysWith: { first, _ in first })
    }

    private var lessonAssignmentsByID: [UUID: CDLessonAssignment] {
        // Use uniquingKeysWith to handle CloudKit sync duplicates
        Dictionary(
            lessonAssignments.compactMap { la in la.id.map { ($0, la) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Filtered works based on current filter selections
    private var filteredWorks: [CDWorkModel] {
        allWorks.filter { work in
            if completedOnly && work.status != .complete { return false }

            // A one-shot route to a particular record takes precedence over
            // stale local filters. Keep the requested item in the collection
            // long enough to reveal it, without weakening the History scope.
            if let focusedWorkID, work.id == focusedWorkID { return true }

            // Kind filter
            if let kind = selectedKind, work.kind != kind { return false }

            // Status filter
            if !completedOnly,
               !selectedStatuses.isEmpty,
               !selectedStatuses.contains(work.status) { return false }

            // CDStudent filter (check participants)
            if !selectedStudentIDs.isEmpty {
                let workStudentIDs = Set((work.participants as? Set<CDWorkParticipantEntity> ?? []).compactMap {
                    UUID(uuidString: $0.studentID)
                })
                if workStudentIDs.isDisjoint(with: selectedStudentIDs) { return false }
            }

            // Search filter
            if !effectiveSearchText.isEmpty {
                let title = workTitle(work).lowercased()
                let notes = work.latestUnifiedNoteText.lowercased()
                let query = effectiveSearchText.lowercased()
                if !title.contains(query) && !notes.contains(query) { return false }
            }

            return true
        }
    }

    /// Paginated works for display
    private var displayedWorks: [CDWorkModel] {
        filteredWorks.paginated(using: pagination)
    }

    private var focusRevealKey: FocusRevealKey {
        FocusRevealKey(
            id: focusedWorkID,
            filteredIndex: focusedWorkID.flatMap { id in
                filteredWorks.firstIndex { $0.id == id }
            }
        )
    }

    private func linkedLessonAssignment(for work: CDWorkModel) -> CDLessonAssignment? {
        guard let idString = work.presentationID,
              let id = UUID(uuidString: idString) else { return nil }
        return lessonAssignmentsByID[id]
    }

    private func linkedLesson(for work: CDWorkModel) -> CDLesson? {
        guard let la = linkedLessonAssignment(for: work) else { return nil }
        // CloudKit compatibility: Convert String lessonID to UUID for lookup
        guard let lessonIDUUID = la.lessonIDUUID else { return nil }
        return lessonsByID[lessonIDUUID]
    }

    private func workTitle(_ work: CDWorkModel) -> String {
        let title = work.title.trimmed()
        if !title.isEmpty { return title }
        let kindLabel = (work.kind ?? .research).shortLabel
        if let lesson = linkedLesson(for: work) { return "\(kindLabel): \(lesson.name)" }
        return kindLabel
    }

    private func workSubtitle(_ work: CDWorkModel) -> String {
        let date: Date = {
            if let la = linkedLessonAssignment(for: work) {
                return la.presentedAt ?? la.scheduledFor ?? la.createdAt ?? Date()
            }
            return work.createdAt ?? Date()
        }()
        let dateString = DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
        if let lesson = linkedLesson(for: work) {
            let area = lesson.area.trimmed()
            return area.isEmpty ? dateString : "\(area) • \(dateString)"
        }
        return dateString
    }

    @ViewBuilder
    private func workDetailSheetContent(for work: CDWorkModel) -> some View {
        WorkDetailView(workID: work.id ?? UUID(), onDone: {
            selectedWork = nil
        })
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 640)
        .presentationSizingFitted()
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }

    // MARK: - Filter Labels

    private var selectedKindLabel: String {
        selectedKind?.displayName ?? "All Types"
    }

    private var selectedStatusLabel: String {
        if selectedStatuses.isEmpty {
            return "All Statuses"
        } else if selectedStatuses.count == 1, let status = selectedStatuses.first {
            return status.displayName
        } else {
            return "\(selectedStatuses.count) Statuses"
        }
    }

    private var selectedStudentLabel: String {
        if selectedStudentIDs.isEmpty {
            return "All Students"
        } else if selectedStudentIDs.count == 1, let id = selectedStudentIDs.first,
                  let student = students.first(where: { $0.id == id }) {
            return displayName(for: student)
        } else {
            return "\(selectedStudentIDs.count) Students"
        }
    }

    private func displayName(for student: CDStudent) -> String {
        let first = student.firstName.trimmed()
        let last = student.lastName.trimmed()
        let li = last.first.map { String($0).uppercased() } ?? ""
        return li.isEmpty ? first : "\(first) \(li)."
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 12) {
            // CDStudent Menu
            Menu {
                Button("All Students") { selectedStudentIDs.removeAll() }
                Divider()
                ForEach(students) { student in
                    if let studentID = student.id {
                        Button(action: {
                            if selectedStudentIDs.contains(studentID) {
                                selectedStudentIDs.remove(studentID)
                            } else {
                                selectedStudentIDs.insert(studentID)
                            }
                        }, label: {
                            HStack {
                                if selectedStudentIDs.contains(studentID) {
                                    Image(systemName: "checkmark")
                                }
                                Text(displayName(for: student))
                            }
                        })
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.3")
                    Text(selectedStudentLabel)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(UIConstants.OpacityConstants.hint))
                )
            }

            // Work Type Menu
            Menu {
                Button("All Types") { selectedKind = nil }
                Divider()
                ForEach(WorkKind.allCases) { kind in
                    Button(action: { selectedKind = kind }, label: {
                        HStack {
                            if selectedKind == kind {
                                Image(systemName: "checkmark")
                            }
                            Text(kind.displayName)
                        }
                    })
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text(selectedKindLabel)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(UIConstants.OpacityConstants.hint))
                )
            }

            if !completedOnly {
                // Status Menu (multi-select)
                Menu {
                    Button("All Statuses") { selectedStatuses.removeAll() }
                    Divider()
                    ForEach(WorkStatus.allCases) { status in
                        Button(action: {
                            if selectedStatuses.contains(status) {
                                selectedStatuses.remove(status)
                            } else {
                                selectedStatuses.insert(status)
                            }
                        }, label: {
                            HStack {
                                if selectedStatuses.contains(status) {
                                    Image(systemName: "checkmark")
                                }
                                Text(status.displayName)
                            }
                        })
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle")
                        Text(selectedStatusLabel)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(UIConstants.OpacityConstants.hint))
                    )
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Body

    private var worksContent: some View {
        VStack(spacing: 8) {
            filterBar

            ScrollViewReader { reader in
                List {
                    ForEach(displayedWorks) { work in
                        let workID = work.id ?? UUID()
                        WorkCard.list(
                            work: work,
                            title: workTitle(work),
                            subtitle: workSubtitle(work),
                            badge: .status(work.isOpen ? "active" : "complete"),
                            onOpen: openWork
                        )
                        .id(workID)
                        .listRowBackground(
                            workID == focusedWorkID
                                ? Color.accentColor.opacity(0.12)
                                : Color.clear
                        )
                    }

                    // Pagination footer
                    if pagination.totalCount > 0 {
                        Section {
                            PaginatedListFooter(state: pagination, itemName: "works")
                        }
                    }
                }
                .listStyle(.inset)
                .task(id: focusRevealKey) {
                    guard let focusedWorkID,
                          let index = filteredWorks.firstIndex(where: { $0.id == focusedWorkID }) else {
                        return
                    }
                    pagination.updateTotal(filteredWorks.count)
                    pagination.revealItem(at: index)
                    await Task.yield()
                    try? await Task.sleep(for: .milliseconds(50))
                    guard !Task.isCancelled else { return }
                    withAnimation { reader.scrollTo(focusedWorkID, anchor: .center) }
                }
            }
        }
    }

    @ViewBuilder
    private var searchableContent: some View {
        if embeddedSearchText == nil {
            worksContent.searchable(text: $searchText)
        } else {
            worksContent
        }
    }

    var body: some View {
        Group {
            if isEmbedded {
                searchableContent
            } else {
                searchableContent.navigationTitle("Works")
            }
        }
        .onChange(of: filteredWorks.count) { _, newCount in
            pagination.updateTotal(newCount)
        }
        .onAppear {
            pagination.updateTotal(filteredWorks.count)
        }
        .sheet(isPresented: Binding(
            get: { selectedWork != nil },
            set: { if !$0 { selectedWork = nil } }
        )) {
            if let work = selectedWork {
                workDetailSheetContent(for: work)
            }
        }
    }

    private func openWork(_ work: CDWorkModel) {
        guard let workID = work.id else { return }
        #if os(macOS)
        openWindow(id: "WorkDetailWindow", value: workID)
        #else
        selectedWork = work
        #endif
    }
}

#Preview {
    WorksLogView()
        .previewEnvironment()
}
