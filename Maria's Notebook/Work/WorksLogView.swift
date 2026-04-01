import SwiftUI
import CoreData

struct WorksLogView: View {
    // Test student filtering
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames)
    private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDWorkModel.createdAt, ascending: false)])
    private var allWorks: FetchedResults<CDWorkModel>

    @FetchRequest(sortDescriptors: []) private var lessons: FetchedResults<CDLesson>
    @FetchRequest(sortDescriptors: []) private var lessonAssignments: FetchedResults<CDLessonAssignment>
    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(keyPath: \CDStudent.firstName, ascending: true),
        NSSortDescriptor(keyPath: \CDStudent.lastName, ascending: true)
    ])
    private var studentsRaw: FetchedResults<CDStudent>
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Filter out test students when setting is disabled
    private var students: [CDStudent] {
        TestStudentsFilter.filterVisible(
            Array(studentsRaw).uniqueByID.filter(\.isEnrolled),
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

    // Pagination state
    @State private var pagination = PaginationState(pageSize: 50)

    private var lessonsByID: [UUID: CDLesson] {
        // Use uniquingKeysWith to handle CloudKit sync duplicates
        Dictionary(lessons.compactMap { l in l.id.map { ($0, l) } }, uniquingKeysWith: { first, _ in first })
    }

    private var lessonAssignmentsByID: [UUID: CDLessonAssignment] {
        // Use uniquingKeysWith to handle CloudKit sync duplicates
        Dictionary(lessonAssignments.compactMap { la in la.id.map { ($0, la) } }, uniquingKeysWith: { first, _ in first })
    }

    /// Filtered works based on current filter selections
    private var filteredWorks: [CDWorkModel] {
        allWorks.filter { work in
            // Kind filter
            if let kind = selectedKind, work.kind != kind { return false }

            // Status filter
            if !selectedStatuses.isEmpty && !selectedStatuses.contains(work.status) { return false }

            // CDStudent filter (check participants)
            if !selectedStudentIDs.isEmpty {
                let workStudentIDs = Set((work.participants as? Set<CDWorkParticipantEntity> ?? []).compactMap {
                    UUID(uuidString: $0.studentID)
                })
                if workStudentIDs.isDisjoint(with: selectedStudentIDs) { return false }
            }

            // Search filter
            if !searchText.isEmpty {
                let title = workTitle(work).lowercased()
                let notes = work.latestUnifiedNoteText.lowercased()
                let query = searchText.lowercased()
                if !title.contains(query) && !notes.contains(query) { return false }
            }

            return true
        }
    }

    /// Paginated works for display
    private var displayedWorks: [CDWorkModel] {
        filteredWorks.paginated(using: pagination)
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
            let subject = lesson.subject.trimmed()
            return subject.isEmpty ? dateString : "\(subject) • \(dateString)"
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
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(UIConstants.OpacityConstants.hint)))
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
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(UIConstants.OpacityConstants.hint)))
            }

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
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(UIConstants.OpacityConstants.hint)))
            }

            Spacer()
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 8) {
            filterBar

            List {
                ForEach(displayedWorks) { work in
                    WorkCard.list(
                        work: work,
                        title: workTitle(work),
                        subtitle: workSubtitle(work),
                        badge: .status(work.isOpen ? "active" : "complete"),
                        onOpen: { w in selectedWork = w }
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
        }
        .navigationTitle("Works")
        .searchable(text: $searchText)
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
}

#Preview {
    WorksLogView()
        .previewEnvironment()
}
