import SwiftUI
import CoreData

struct StudentPickerPopover: View {
    let students: [CDStudent]
    @Binding var selectedIDs: Set<UUID>
    var onDone: (() -> Void)?
    /// When false the footer offers "Show All" instead of "New Student…". Filter call sites
    /// want to widen the selection back out, not create a student mid-filter.
    var allowsCreatingStudents: Bool = true

    @State private var filterLevel: LevelFilter = .all
    @State private var searchText: String = ""
    @State private var showingAddStudent: Bool = false

    @AppStorage(UserDefaultsKeys.studentPickerSortOrder)
    private var sortModeRaw: String = SortMode.name.rawValue

    @Environment(\.dismiss) private var dismiss

    enum LevelFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case lower = "Lower"
        case upper = "Upper"
        case adolescent = "Adolescent"

        var id: String { rawValue }
    }

    /// How the list is ordered. Age is for the common case of picking a run of children
    /// who are close in age; the ages are listed either way so the choice is visible.
    enum SortMode: String, CaseIterable, Identifiable {
        case name
        case age

        var id: String { rawValue }

        var title: String {
            switch self {
            case .name: return "Name"
            case .age: return "Age"
            }
        }

        var systemImage: String {
            switch self {
            case .name: return "textformat.abc"
            case .age: return "calendar"
            }
        }
    }

    private var sortMode: SortMode { SortMode(rawValue: sortModeRaw) ?? .name }

    var filteredStudentsForPicker: [CDStudent] {
        let search = searchText.normalizedForComparison()
        let enrolled = students.filterEnrolled()

        let searched = enrolled.filter { student in
            if search.isEmpty { return true }
            let first = student.firstName.lowercased()
            let last = student.lastName.lowercased()
            let full = "\(first) \(last)"
            return first.contains(search) || last.contains(search) || full.contains(search)
        }

        let filtered = searched.filter { student in
            switch filterLevel {
            case .all:
                return true
            case .lower:
                return student.level == .lower
            case .upper:
                return student.level == .upper
            case .adolescent:
                return student.level == .adolescent
            }
        }

        return sortedForDisplay(filtered)
    }

    /// Age runs oldest first, matching the student columns on the checklist this picker
    /// filters, so the same children sit in the same order in both places. Students with
    /// no birthday on file sink to the bottom rather than posing as newborns.
    private func sortedForDisplay(_ students: [CDStudent]) -> [CDStudent] {
        switch sortMode {
        case .name:
            return students.sorted(by: StudentSortComparator.byFirstName)
        case .age:
            return students.sorted { lhs, rhs in
                switch (lhs.birthday, rhs.birthday) {
                case let (left?, right?):
                    if left != right { return left < right }
                    return StudentSortComparator.byFirstName(lhs, rhs)
                case (nil, nil):
                    return StudentSortComparator.byFirstName(lhs, rhs)
                case (nil, _):
                    return false
                case (_, nil):
                    return true
                }
            }
        }
    }
    
    func displayName(for student: CDStudent) -> String {
        return StudentFormatter.displayName(for: student)
    }

    /// IDs of the students the current search and level filter leave on screen. The
    /// select-all control acts on exactly this set, so what you see is what you toggle.
    private var visibleStudentIDs: [UUID] {
        filteredStudentsForPicker.compactMap(\.id)
    }

    private var allVisibleSelected: Bool {
        !visibleStudentIDs.isEmpty && visibleStudentIDs.allSatisfy { selectedIDs.contains($0) }
    }

    /// The name of the group being toggled, when the visible set is a whole level rather
    /// than a search result. Lets the button read "Select All Upper".
    private var visibleScopeName: String? {
        guard searchText.normalizedForComparison().isEmpty else { return nil }
        switch filterLevel {
        case .all: return nil
        case .lower: return "Lower"
        case .upper: return "Upper"
        case .adolescent: return "Adolescent"
        }
    }

    private var selectAllTitle: String {
        guard let scope = visibleScopeName else {
            return allVisibleSelected ? "Deselect These" : "Select These"
        }
        return allVisibleSelected ? "Deselect \(scope)" : "Select All \(scope)"
    }

    private func toggleSelectAllVisible() {
        let ids = visibleStudentIDs
        guard !ids.isEmpty else { return }
        adaptiveWithAnimation {
            if allVisibleSelected {
                selectedIDs.subtract(ids)
            } else {
                selectedIDs.formUnion(ids)
            }
        }
    }

    /// Ordering control. Sits next to the select-all button rather than in its own row so
    /// the popover keeps its height.
    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $sortModeRaw) {
                ForEach(SortMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage)
                        .tag(mode.rawValue)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(sortMode.title, systemImage: "arrow.up.arrow.down")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Sort students")
    }

    @ViewBuilder
    private func studentRow(for student: CDStudent) -> some View {
        let isSelected = student.id.map { selectedIDs.contains($0) } ?? false
        HStack(spacing: 8) {
            Text(displayName(for: student))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            if let birthday = student.birthday {
                Text(AgeUtils.quarterGlyphAgeString(for: birthday))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(AgeUtils.verboseQuarterAgeString(for: birthday))
            }

            // The tick keeps its slot when a row is unselected, so the ages stay in a column.
            Image(systemName: "checkmark")
                .foregroundStyle(Color.accentColor)
                .opacity(isSelected ? 1 : 0)
                .accessibilityHidden(!isSelected)
                .frame(width: 14)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Search…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
#if os(iOS) || os(tvOS) || os(visionOS)
                    .textInputAutocapitalization(.never)
#endif

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Picker("Level", selection: $filterLevel) {
                ForEach(LevelFilter.allCases) { level in
                    Text(level.rawValue).tag(level)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Button(selectAllTitle) {
                    toggleSelectAllVisible()
                }
                .buttonStyle(.borderless)
                .font(.callout)
                .disabled(visibleStudentIDs.isEmpty)

                Spacer()

                if !selectedIDs.isEmpty {
                    Text("\(selectedIDs.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                sortMenu
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(filteredStudentsForPicker) { student in
                        Button {
                            adaptiveWithAnimation {
                                guard let studentID = student.id else { return }
                                if selectedIDs.contains(studentID) {
                                    selectedIDs.remove(studentID)
                                } else {
                                    selectedIDs.insert(studentID)
                                }
                            }
                        } label: {
                            studentRow(for: student)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }

            Divider()

            HStack {
                if allowsCreatingStudents {
                    Button("New Student…") {
                        showingAddStudent = true
                    }
                } else {
                    Button("Show All") {
                        selectedIDs.removeAll()
                    }
                    .disabled(selectedIDs.isEmpty)
                }

                Spacer()

                Button("Done") {
                    if let onDone {
                        onDone()
                    } else {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(minWidth: 320)
        .sheet(isPresented: $showingAddStudent) {
            AddStudentView()
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
