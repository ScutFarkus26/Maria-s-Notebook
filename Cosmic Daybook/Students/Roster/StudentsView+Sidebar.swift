import SwiftUI
import CoreData

// MARK: - Sidebar (Roster List, iPhone and iPad)

extension StudentsView {

    func sidebarColumn(_ snapshot: RosterSnapshot) -> some View {
        rosterList(snapshot)
            .navigationTitle("Students")
            .inlineNavigationTitle()
            .navigationSplitViewColumnWidth(min: 320, ideal: 380)
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search students")
            .onSubmit(of: .search) {
                if let first = snapshot.shown.first {
                    selectedStudentID = first.id
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if !uniqueStudents.isEmpty {
                    chipsHeader(snapshot)
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

    private func chipsHeader(_ snapshot: RosterSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            StudentsScopeChips(
                scopes: snapshot.scopes,
                selectedFilter: selectedFilter,
                onSelect: { filter in studentsFilterRaw = filter.storageValue }
            )
            if viewModel.showsAttendanceNotTaken {
                Label("Attendance not taken yet", systemImage: "checklist")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private func rosterList(_ snapshot: RosterSnapshot) -> some View {
        if uniqueStudents.isEmpty {
            NoStudentsEmptyState { showingAddStudent = true }
        } else if snapshot.shown.isEmpty && snapshot.former.isEmpty {
            emptyFilterState
        } else {
            List(selection: $selectedStudentID) {
                ForEach(levelSections(of: snapshot.shown), id: \.level) { section in
                    Section {
                        ForEach(section.students, id: \.objectID) { student in
                            listRow(for: student)
                        }
                        .onMove(perform: manualMoveHandler(for: section.students))
                    } header: {
                        Text("\(section.title) · \(section.students.count)")
                    }
                }
                withdrawnSection(snapshot.former)
            }
            .quickCaptureButtonClearance()
        }
    }

    private struct LevelSection {
        let level: CDStudent.Level
        let students: [CDStudent]

        var title: String {
            switch level {
            case .lower: return "Lower Elementary"
            case .upper: return "Upper Elementary"
            case .adolescent: return "Adolescent"
            }
        }
    }

    /// The shown children grouped by level, youngest level first, each group
    /// keeping the active sort.
    private func levelSections(of students: [CDStudent]) -> [LevelSection] {
        let byLevel = Dictionary(grouping: students, by: \.level)
        return CDStudent.Level.allCases.compactMap { level in
            guard let group = byLevel[level], !group.isEmpty else { return nil }
            return LevelSection(level: level, students: group)
        }
    }

    /// Reordering is only available in manual sort; nil disables the move affordance.
    private func manualMoveHandler(for subset: [CDStudent]) -> ((IndexSet, Int) -> Void)? {
        guard sortOrder == .manual else { return nil }
        return { source, destination in
            handleManualReorder(from: source, to: destination, in: subset)
        }
    }

    @ViewBuilder
    private var emptyFilterState: some View {
        if selectedFilter == .presentNow && !viewModel.attendanceTaken {
            NoAttendanceEmptyState {
                studentsFilterRaw = StudentsFilter.all.storageValue
            }
        } else if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else if selectedFilter == .dueForLesson {
            ContentUnavailableView {
                Label("No One Is Due", systemImage: "checkmark.circle")
            } description: {
                Text("Everyone has had a lesson in the last \(RosterSignalRules.dueSchoolDays) school days.")
            } actions: {
                Button("Show All Students") {
                    studentsFilterRaw = StudentsFilter.all.storageValue
                }
            }
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
            signals: withdrawn ? nil : viewModel.signals(for: student.id),
            onAddObservation: withdrawn ? nil : { addObservation(for: student) },
            onGiveLesson: withdrawn ? nil : { giveLesson(to: student) }
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !withdrawn {
                Button {
                    giveLesson(to: student)
                } label: {
                    Label("Lesson", systemImage: "book")
                }
                .tint(.orange)
                Button {
                    addObservation(for: student)
                } label: {
                    Label("Observe", systemImage: "square.and.pencil")
                }
                .tint(.blue)
            }
        }
        if let id = student.id {
            row.tag(id)
        } else {
            row.selectionDisabled()
        }
    }

    @ViewBuilder
    private func withdrawnSection(_ former: [CDStudent]) -> some View {
        if !former.isEmpty {
            Section {
                if isWithdrawnExpanded {
                    ForEach(former, id: \.objectID) { student in
                        listRow(for: student, withdrawn: true)
                    }
                }
            } header: {
                Button {
                    withAnimation { isWithdrawnExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text("Former Students (\(former.count))")
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
