import SwiftUI
import CoreData

struct WorksLogView: View {
    var embeddedSearchText: String?
    var completedOnly: Bool = false
    var isEmbedded: Bool = false
    var focusedWorkID: UUID?

    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    // Test student filtering
    @TestStudentVisibility private var testStudents

    @FetchRequest(fetchRequest: {
        let request = CDFetchRequest(CDWorkModel.self)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDWorkModel.createdAt, ascending: false)]
        request.fetchBatchSize = 50
        // Prefetch unifiedNotes so latestUnifiedNoteText doesn't fault the relationship
        // per row (N+1) when filtering/searching the works list, and participants
        // for the per-group visibility a picked child reads (WorkVisibility).
        request.relationshipKeyPathsForPrefetching = ["unifiedNotes", "participants"]
        return request
    }())
    private var allWorks: FetchedResults<CDWorkModel>

    @Environment(\.dependencies) private var dependencies

    @FetchRequest(sortDescriptors: []) private var lessonAssignments: FetchedResults<CDLessonAssignment>

    // Filter out test students when setting is disabled.
    // All students, not enrolled-only: this log spans all time, so former
    // students' work history must keep resolving.
    private var students: [CDStudent] {
        TestStudentsFilter.filterVisible(
            dependencies.roster.all,
            show: testStudents.show,
            namesRaw: testStudents.namesRaw
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

    private var lessonsByID: [UUID: CDLesson] { dependencies.lessonCatalog.byID }

    /// Built once per `body` pass and handed to every row. It used to be a
    /// computed property rebuilt on every lookup — twice or three times per row
    /// drawn, and once per work item whenever a search was typed.
    private var lessonAssignmentsByID: [UUID: CDLessonAssignment] {
        // Use uniquingKeysWith to handle CloudKit sync duplicates
        Dictionary(
            lessonAssignments.compactMap { la in la.id.map { ($0, la) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Filtered works based on current filter selections
    private func filteredWorks(using assignmentsByID: [UUID: CDLessonAssignment]) -> [CDWorkModel] {
        // Whose each row is, read per linked group. `allWorks` is the whole
        // table, so every row's group is already in hand; only built while a
        // child is picked.
        let visibility = WorkVisibility(rows: selectedStudentIDs.isEmpty ? [] : Array(allWorks))
        return allWorks.filter { work in
            if completedOnly && work.status.isOpen { return false }

            // A one-shot route to a particular record takes precedence over
            // stale local filters. Keep the requested item in the collection
            // long enough to reveal it, without weakening the History scope.
            if let focusedWorkID, work.id == focusedWorkID { return true }

            if !WorksLogRows.matches(work, kind: selectedKind) { return false }

            // Status filter
            if !WorksLogRows.matches(work, statuses: selectedStatuses) { return false }

            if !WorksLogRows.matches(work, students: selectedStudentIDs, visibility: visibility) { return false }

            // Search filter
            // (title, notes, and the child it is for, as the live list reads them)
            if !effectiveSearchText.isEmpty {
                var texts = [workTitle(work, assignmentsByID), work.latestUnifiedNoteText]
                for id in HistorySearch.searchedStudentIDs(of: work) {
                    if let student = dependencies.roster.byID[id] { texts += HistorySearch.names(of: student) }
                }
                if !HistorySearch.matches(effectiveSearchText, in: texts) { return false }
            }

            return true
        }
    }

    private func focusRevealKey(_ filteredWorks: [CDWorkModel]) -> FocusRevealKey {
        FocusRevealKey(
            id: focusedWorkID,
            filteredIndex: focusedWorkID.flatMap { id in
                filteredWorks.firstIndex { $0.id == id }
            }
        )
    }

    private func linkedLessonAssignment(
        for work: CDWorkModel, _ assignmentsByID: [UUID: CDLessonAssignment]
    ) -> CDLessonAssignment? {
        guard let idString = work.presentationID,
              let id = UUID(uuidString: idString) else { return nil }
        return assignmentsByID[id]
    }

    private func linkedLesson(
        for work: CDWorkModel, _ assignmentsByID: [UUID: CDLessonAssignment]
    ) -> CDLesson? {
        guard let la = linkedLessonAssignment(for: work, assignmentsByID) else { return nil }
        // CloudKit compatibility: Convert String lessonID to UUID for lookup
        guard let lessonIDUUID = la.lessonIDUUID else { return nil }
        return lessonsByID[lessonIDUUID]
    }

    private func workTitle(_ work: CDWorkModel, _ assignmentsByID: [UUID: CDLessonAssignment]) -> String {
        WorksLogRows.title(
            of: work, linkedLesson: linkedLesson(for: work, assignmentsByID), lessonsByID: lessonsByID
        )
    }

    private func workSubtitle(_ work: CDWorkModel, _ assignmentsByID: [UUID: CDLessonAssignment]) -> String {
        let date: Date = {
            if let la = linkedLessonAssignment(for: work, assignmentsByID) {
                return la.presentedAt ?? la.scheduledFor ?? la.createdAt ?? Date()
            }
            return work.createdAt ?? Date()
        }()
        let dateString = DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
        if let lesson = WorksLogRows.lesson(
            of: work, linkedLesson: linkedLesson(for: work, assignmentsByID), lessonsByID: lessonsByID
        ) {
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

    // MARK: - Filter Bar

    private var statusChoices: [WorkStatus] {
        WorksLogRows.statusChoices(completedOnly: completedOnly)
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            MultiSelectFilterMenu(
                items: students,
                selection: $selectedStudentIDs,
                id: { $0.id },
                label: { $0.shortName },
                summary: FilterSelectionSummary(allLabel: "All Students"),
                systemImage: "person.3"
            )

            SingleSelectFilterMenu(
                items: WorkKind.allCases,
                selection: $selectedKind,
                label: { $0.displayName },
                systemImage: "line.3.horizontal.decrease.circle",
                allLabel: "All Types"
            )

            // History offers only the finished statuses; the open ones live
            // on the Scheduled strip.
            MultiSelectFilterMenu(
                items: statusChoices,
                selection: $selectedStatuses,
                label: { $0.displayName },
                summary: FilterSelectionSummary(allLabel: "All Statuses"),
                systemImage: "checkmark.circle"
            )

            Spacer()
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Body

    private func worksContent(
        _ filteredWorks: [CDWorkModel], _ assignmentsByID: [UUID: CDLessonAssignment]
    ) -> some View {
        VStack(spacing: 8) {
            filterBar

            ScrollViewReader { reader in
                List {
                    ForEach(filteredWorks.paginated(using: pagination)) { work in
                        let workID = work.id ?? UUID()
                        WorkCard.list(
                            work: work,
                            title: workTitle(work, assignmentsByID),
                            subtitle: workSubtitle(work, assignmentsByID),
                            badge: .status(work.status.displayName.lowercased()),
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
                            PaginatedListFooter(state: pagination, itemName: "work items")
                        }
                    }
                }
                .listStyle(.inset)
                .task(id: focusRevealKey(filteredWorks)) {
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
    private func searchableContent(
        _ filteredWorks: [CDWorkModel], _ assignmentsByID: [UUID: CDLessonAssignment]
    ) -> some View {
        if embeddedSearchText == nil {
            worksContent(filteredWorks, assignmentsByID).searchable(text: $searchText)
        } else {
            worksContent(filteredWorks, assignmentsByID)
        }
    }

    var body: some View {
        // One lookup and one filter pass per render, shared by every row, the
        // reveal task and the pagination count.
        let assignmentsByID = lessonAssignmentsByID
        let filtered = filteredWorks(using: assignmentsByID)
        Group {
            if isEmbedded {
                searchableContent(filtered, assignmentsByID)
            } else {
                searchableContent(filtered, assignmentsByID).navigationTitle("Works")
            }
        }
        .onChange(of: filtered.count) { _, newCount in
            pagination.updateTotal(newCount)
        }
        .onAppear {
            pagination.updateTotal(filtered.count)
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

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct WorksLogViewPreview: View {
    var body: some View {
        WorksLogView()
            .previewEnvironment()
    }
}

#Preview {
    WorksLogViewPreview()
}
