import SwiftUI
import CoreData

// MARK: - Sidebar (Roster List)

extension StudentsView {

    #if os(macOS)
    /// The first column in the Mac workspace is a real collection sidebar, not
    /// a second copy of the roster. The adjacent roster/table and record panes
    /// make browsing and comparison feel at home on a desktop.
    var workspaceSidebarColumn: some View {
        List {
            Section("Students") {
                workspaceScopeRow(.all, count: enrolledCount, systemImage: "person.3")
                workspaceScopeRow(.presentNow, count: presentNowCount, systemImage: "checkmark.circle")
            }

            Section("Level") {
                workspaceScopeRow(.lower, systemImage: "circle.fill")
                workspaceScopeRow(.upper, systemImage: "circle.fill")
            }

            if !withdrawnStudents.isEmpty {
                Section("Records") {
                    Button {
                        isShowingWithdrawnRoster = true
                        selectedStudentID = nil
                    } label: {
                        Label("Withdrawn (\(withdrawnStudents.count))", systemImage: "archivebox")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isShowingWithdrawnRoster ? Color.accentColor : .primary)
                }
            }
        }
        .navigationTitle("Students")
        .inlineNavigationTitle()
        .navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 300)
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search students")
        .onSubmit(of: .search) {
            if let first = macRosterStudents.first {
                selectedStudentID = first.id
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { addStudentMenu }
        }
        .overlay {
            ParsingOverlay(isParsing: $isParsing) {
                parsingTask?.cancel()
            }
        }
        .background {
            Button("") { showingAddStudent = true }
                .keyboardShortcut("n", modifiers: [.command])
                .hidden()
        }
    }

    private func workspaceScopeRow(
        _ filter: StudentsFilter,
        count: Int? = nil,
        systemImage: String
    ) -> some View {
        let isSelected = !isShowingWithdrawnRoster && selectedFilter == filter
        return Button {
            isShowingWithdrawnRoster = false
            studentsFilterRaw = filter.storageValue
        } label: {
            HStack {
                Label(filter.chipTitle, systemImage: systemImage)
                Spacer()
                if let count {
                    Text("\(count)")
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.accentColor : .primary)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
    #endif

    var sidebarColumn: some View {
        rosterList
            .navigationTitle("Students")
            .inlineNavigationTitle()
            .navigationSplitViewColumnWidth(min: 300, ideal: 360)
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search students")
            .onSubmit(of: .search) {
                if let first = filteredStudents.first {
                    selectedStudentID = first.id
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if !uniqueStudents.isEmpty {
                    chipsHeader
                }
            }
            .toolbar { sidebarToolbar }
            .overlay {
                ParsingOverlay(isParsing: $isParsing) {
                    parsingTask?.cancel()
                }
            }
            .background {
                // Keeps ⌘N working regardless of whether the add menu is open.
                Button("") { showingAddStudent = true }
                    .keyboardShortcut("n", modifiers: [.command])
                    .hidden()
            }
    }

    private var chipsHeader: some View {
        VStack(spacing: 0) {
            StudentsScopeChips(
                selectedFilter: selectedFilter,
                allCount: enrolledCount,
                hereCount: presentNowCount,
                onSelect: { filter in studentsFilterRaw = filter.storageValue }
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
        }
        .background(.bar)
    }

    @ViewBuilder
    private var rosterList: some View {
        if uniqueStudents.isEmpty {
            NoStudentsEmptyState { showingAddStudent = true }
        } else if filteredStudents.isEmpty && withdrawnStudents.isEmpty {
            emptyFilterState
        } else {
            studentsList
        }
    }

    private var studentsList: some View {
        List(selection: $selectedStudentID) {
            enrolledSection
            withdrawnSection
        }
    }

    @ViewBuilder
    private var enrolledSection: some View {
        if !filteredStudents.isEmpty {
            Section {
                ForEach(filteredStudents, id: \.objectID) { student in
                    listRow(for: student)
                }
                .onMove(perform: manualMoveHandler)
            }
        }
    }

    /// Reordering is only available in manual sort; passing nil disables the move affordance.
    private var manualMoveHandler: ((IndexSet, Int) -> Void)? {
        guard sortOrder == .manual else { return nil }
        return { source, destination in
            handleManualReorder(from: source, to: destination)
        }
    }

    @ViewBuilder
    private var emptyFilterState: some View {
        if selectedFilter == .presentNow && presentNowIDs.isEmpty {
            NoAttendanceEmptyState {
                studentsFilterRaw = StudentsFilter.all.storageValue
            }
        } else if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            ContentUnavailableView {
                Label("No Students Match", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Try a different filter.")
            } actions: {
                Button("Show All Students") {
                    studentsFilterRaw = StudentsFilter.all.storageValue
                }
            }
        }
    }

    // The tag must be a non-optional UUID: List(selection: Binding<UUID?>) only
    // matches tags of exactly UUID, so tagging with the optional `student.id`
    // makes every row silently unselectable.
    @ViewBuilder
    private func listRow(for student: CDStudent, withdrawn: Bool = false) -> some View {
        let row = StudentListRow(
            student: student,
            sortOrder: withdrawn ? .alphabetical : sortOrder,
            daysSinceLastLesson: withdrawn ? nil : student.id.flatMap { daysSinceLastLessonByStudent[$0] },
            isPresentToday: !withdrawn && (student.id.map { presentNowIDs.contains($0) } ?? false)
        )
        if let id = student.id {
            row.tag(id)
        } else {
            row.selectionDisabled()
        }
    }

    @ViewBuilder
    private var withdrawnSection: some View {
        if !withdrawnStudents.isEmpty {
            Section {
                if isWithdrawnExpanded {
                    ForEach(withdrawnStudents, id: \.objectID) { student in
                        listRow(for: student, withdrawn: true)
                    }
                }
            } header: {
                Button {
                    withAnimation { isWithdrawnExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text("Withdrawn (\(withdrawnStudents.count))")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .rotationEffect(.degrees(isWithdrawnExpanded ? 90 : 0))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
