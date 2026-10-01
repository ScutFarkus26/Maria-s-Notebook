#if os(macOS)
import SwiftUI
import CoreData

// MARK: - Mac Workspace

extension StudentsView {

    /// The app already supplies the outer navigation split view. Using a
    /// second NavigationSplitView here makes macOS apply that outer sidebar's
    /// safe-area inset again, leaving a false blank column before the table.
    /// HSplitView provides the same user-resizable Mac workspace without
    /// nesting navigation containers.
    ///
    /// Two panes, both always present: the roster table under its scope bar,
    /// and the open record — or the class at a glance — beside it, so the
    /// table never jumps width when a child is selected.
    func macWorkspace(_ snapshot: RosterSnapshot) -> some View {
        HSplitView {
            macRosterColumn(snapshot)
                .frame(minWidth: 460, idealWidth: 680)

            macDetailColumn(snapshot)
                .frame(minWidth: 420, idealWidth: 620)
        }
        .navigationTitle(isShowingWithdrawnRoster ? "Former Students" : "Students")
        .navigationSubtitle(macSubtitle(snapshot))
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search students")
        .onSubmit(of: .search) {
            let rows = isShowingWithdrawnRoster ? snapshot.former : snapshot.shown
            if let first = rows.first { selectedStudentID = first.id }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { addStudentMenu }
        }
        .overlay {
            ParsingOverlay(isParsing: $isParsing) {
                parsingTask?.cancel()
            }
        }
    }

    private func macSubtitle(_ snapshot: RosterSnapshot) -> String {
        if isShowingWithdrawnRoster { return "\(snapshot.former.count) former" }
        let here = snapshot.scopes.first { $0.filter == .presentNow }?.count ?? 0
        let enrolled = "\(snapshot.enrolled.count) enrolled"
        return viewModel.attendanceTaken ? "\(enrolled) · \(here) here today" : enrolled
    }

    private func macRosterColumn(_ snapshot: RosterSnapshot) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                StudentsScopeChips(
                    scopes: snapshot.scopes,
                    selectedFilter: isShowingWithdrawnRoster ? .withdrawn : selectedFilter,
                    onSelect: { filter in
                        isShowingWithdrawnRoster = false
                        studentsFilterRaw = filter.storageValue
                    }
                )
                if !snapshot.former.isEmpty || isShowingWithdrawnRoster {
                    Toggle(isOn: formerToggle) {
                        Text("Former (\(snapshot.former.count))")
                    }
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .fixedSize()
                    .help("Show students who have left the class")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if viewModel.showsAttendanceNotTaken && !isShowingWithdrawnRoster {
                Label("Attendance not taken yet", systemImage: "checklist")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }

            Divider()

            StudentsTableView(
                students: isShowingWithdrawnRoster ? snapshot.former : snapshot.shown,
                signals: { viewModel.signals(for: $0) },
                showsSignals: !isShowingWithdrawnRoster,
                selectedStudentID: $selectedStudentID,
                onAddObservation: addObservation(for:),
                onGiveLesson: giveLesson(to:)
            )
        }
        .background {
            Button("") { showingAddStudent = true }
                .keyboardShortcut("n", modifiers: [.command])
                .hidden()
        }
    }

    private var formerToggle: Binding<Bool> {
        Binding(
            get: { isShowingWithdrawnRoster },
            set: { isOn in
                isShowingWithdrawnRoster = isOn
                selectedStudentID = nil
            }
        )
    }

    @ViewBuilder
    private func macDetailColumn(_ snapshot: RosterSnapshot) -> some View {
        if let student = selectedStudent {
            studentRecord(student)
        } else {
            classGlance(snapshot)
        }
    }
}
#endif
