//
//  StudentPickerPopover.swift
//  Cosmic Daybook
//
//  The roster in a popover: search it, scope it to a level, sort it, tick the
//  children you want.
//
//  Which children it offers, in what order, and which of them may not be
//  ticked at all is `StudentPickerModel` — value types with their own tests.
//  This file is the presentation of those rows and nothing else.
//
//  The present-a-lesson caller arranges it Selected → Ready → Everyone Else
//  (`arrangement: .selectedThenReady`), with a header over each run and no
//  sort menu; the Ready run is `ReadyGroups.readyStudentIDs`, read once per
//  lesson. Every picker offers only the levels its enrolled children are at.
//

import SwiftUI
import CoreData

struct StudentPickerPopover: View {
    let students: [CDStudent]
    @Binding var selectedIDs: Set<UUID>
    var onDone: (() -> Void)?
    /// When false the footer offers "Show All" instead of "New Student…". Filter call sites
    /// want to widen the selection back out, not create a student mid-filter.
    var allowsCreatingStudents: Bool = true
    /// The lesson the group being picked is for, when there is one. Given it,
    /// each row says whether the record already has that child on this lesson —
    /// the same caption the schedule sheet shows. Note and filter call sites
    /// have no lesson and leave it nil.
    var lessonOnRecord: CDLesson?
    /// What to do with a child who has left the classroom. Forming a group for
    /// a lesson shows her disabled with the reason, so a withdrawal is visible
    /// where the choice is made; every other picker keeps today's behaviour and
    /// leaves her out.
    var formerStudents: StudentPickerModel.FormerStudents = .hidden
    /// How the rows are ordered. The remembered sort menu by default; the
    /// present-a-lesson picker puts the picked and the ready children first.
    var arrangement: StudentPickerModel.Arrangement = .sortMenu

    @State private var filterLevel: LevelFilter = .all
    @State private var searchText: String = ""
    @State private var showingAddStudent: Bool = false
    /// What the record holds for `lessonOnRecord`, read once when there is one.
    @State private var records: [UUID: PresentationRecordIndex.Given] = [:]
    /// Who is ready for `lessonOnRecord`, read once when the picker is
    /// arranged around it.
    @State private var readyIDs: Set<UUID> = []
    /// The selection as the picker opened: the Selected run. Until it is
    /// captured the live selection stands in, which is the same set.
    @State private var openingSelection: Set<UUID>?

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies

    @AppStorage(UserDefaultsKeys.studentPickerSortOrder)
    private var sortModeRaw: String = SortMode.name.rawValue

    @Environment(\.dismiss) private var dismiss

    enum LevelFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case lower = "Lower"
        case upper = "Upper"
        case adolescent = "Adolescent"

        var id: String { rawValue }

        var level: CDStudent.Level? {
            switch self {
            case .all: return nil
            case .lower: return .lower
            case .upper: return .upper
            case .adolescent: return .adolescent
            }
        }

        var scope: StudentPickerModel.LevelScope {
            level.map(StudentPickerModel.LevelScope.level) ?? .all
        }
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

        var sort: StudentPickerModel.Sort {
            switch self {
            case .name: return .name
            case .age: return .age
            }
        }
    }

    private var sortMode: SortMode { SortMode(rawValue: sortModeRaw) ?? .name }

    private var candidates: [StudentPickerCandidate] { StudentPickerModel.candidates(students) }

    /// The level segments on offer: All, then each level an enrolled child is
    /// at. Fewer than two levels leave nothing to choose between.
    private var offeredLevelFilters: [LevelFilter] {
        let levels = StudentPickerModel.offeredLevels(candidates)
        guard levels.count > 1 else { return [] }
        return [.all] + LevelFilter.allCases.filter { $0.level.map(levels.contains) ?? false }
    }

    /// The chosen segment, or All when that level is no longer on offer.
    private var effectiveLevel: LevelFilter {
        offeredLevelFilters.contains(filterLevel) ? filterLevel : .all
    }

    /// The children on screen, with what the record holds for each and whether
    /// she may be picked.
    var rows: [StudentPickerRow] {
        StudentPickerModel.rows(
            candidates: candidates,
            query: StudentPickerModel.Query(
                search: searchText,
                scope: effectiveLevel.scope,
                sort: sortMode.sort,
                formerStudents: formerStudents,
                arrangement: arrangement,
                pinned: openingSelection ?? selectedIDs,
                ready: readyIDs
            ),
            records: records
        )
    }

    /// IDs of the children the current search and level filter leave on screen and
    /// allow picking. The select-all control acts on exactly this set.
    private var selectableIDs: [UUID] { StudentPickerModel.selectableIDs(rows) }

    private var allVisibleSelected: Bool {
        !selectableIDs.isEmpty && selectableIDs.allSatisfy { selectedIDs.contains($0) }
    }

    /// Nothing on screen can be ticked — every row is a child who has left, or
    /// the search found nobody.
    private var nothingSelectable: Bool { selectableIDs.isEmpty }

    /// The name of the group being toggled, when the visible set is a whole level rather
    /// than a search result. Lets the button read "Select All Upper".
    private var visibleScopeName: String? {
        guard searchText.normalizedForComparison().isEmpty else { return nil }
        return effectiveLevel.level?.rawValue
    }

    private var selectAllTitle: String {
        guard let scope = visibleScopeName else {
            return allVisibleSelected ? "Deselect These" : "Select These"
        }
        return allVisibleSelected ? "Deselect \(scope)" : "Select All \(scope)"
    }

    private func toggleSelectAllVisible() {
        let visible = rows
        guard !StudentPickerModel.selectableIDs(visible).isEmpty else { return }
        adaptiveWithAnimation {
            selectedIDs = StudentPickerModel.selectAll(visible, in: selectedIDs)
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

    var body: some View {
        VStack(spacing: 12) {
            searchAndLevelControls

            HStack {
                Button(selectAllTitle) {
                    toggleSelectAllVisible()
                }
                .buttonStyle(.borderless)
                .font(.callout)
                .disabled(nothingSelectable)

                Spacer()

                if !selectedIDs.isEmpty {
                    Text("\(selectedIDs.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if arrangement == .sortMenu {
                    sortMenu
                }
            }

            studentList

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
        .onAppear {
            if openingSelection == nil { openingSelection = selectedIDs }
        }
        .task(id: lessonOnRecord?.id) { loadRecord() }
    }

}

// MARK: - Rows and the Lesson's Record

extension StudentPickerPopover {

    /// The search field and level segments. Split out of `body` to keep either
    /// half inside the 100 ms type-check budget.
    var searchAndLevelControls: some View {
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

            let levels = offeredLevelFilters
            if !levels.isEmpty {
                Picker("Level", selection: $filterLevel) {
                    ForEach(levels) { level in
                        Text(level.rawValue).tag(level)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    /// The scrolling roster. Split out of `body` to keep either half inside
    /// the 100 ms type-check budget.
    var studentList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(StudentPickerModel.sections(rows), id: \.placement) { section in
                    if let placement = section.placement {
                        Section {
                            rowViews(section.rows)
                        } header: {
                            sectionHeader(placement)
                        }
                    } else {
                        rowViews(section.rows)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func rowViews(_ rows: [StudentPickerRow]) -> some View {
        ForEach(rows) { row in
            StudentPickerRowView(
                row: row,
                isSelected: selectedIDs.contains(row.id),
                onToggle: { toggle(row.id) }
            )
        }
    }

    private func sectionHeader(_ placement: StudentPickerModel.Placement) -> some View {
        Text(placement.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.top, placement == .selected ? 0 : 8)
            .accessibilityAddTraits(.isHeader)
    }

    private func toggle(_ id: UUID) {
        let visible = rows
        adaptiveWithAnimation {
            selectedIDs = StudentPickerModel.toggling(id, in: selectedIDs, rows: visible)
        }
    }

    private func loadRecord() {
        guard let lessonID = lessonOnRecord?.id else {
            records = [:]
            readyIDs = []
            return
        }
        let index = PresentationRecordIndex(lessonIDs: [lessonID.uuidString], in: viewContext)
        records = StudentPickerModel.records(from: index, lesson: lessonID)
        readyIDs = arrangement == .selectedThenReady ? loadReady(lessonID) : []
    }

    /// The enrolled children on offer who are ready for the lesson.
    private func loadReady(_ lessonID: UUID) -> Set<UUID> {
        let enrolled = Set(candidates.filter { $0.enrollmentBlock == nil }.map(\.id.uuidString))
        let ready = ReadyGroups.readyStudentIDs(
            for: lessonID.uuidString,
            among: enrolled,
            lessons: dependencies.lessonCatalog.all,
            in: viewContext
        )
        return Set(ready.compactMap(UUID.init(uuidString:)))
    }
}
