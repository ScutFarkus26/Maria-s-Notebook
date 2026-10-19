// ClassGridYearsView.swift
// The Class Grid's Three Years view: every child's furthest mark on the Great
// Lessons and each area ("All areas"), or on an area's sequences and lessons.
// Children are grouped by year in class, oldest first, under a "YEAR 3 · 5"
// band, as the Checklist groups them by level. Click a mark for what's behind
// it; click a row's name for the children in each state and a draft
// presentation for those who haven't had it.
//
// The grid is hand-built, as the Checklist's is: a header row pinned by the
// lazy stack, a name column pinned by the one scroll-offset reading
// (`stickyLeftScrollTracking`), so a full area scrolls without measuring rows.

import CoreData
import SwiftUI

struct ClassGridYearsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(SaveCoordinator.self) private var saveCoordinator
    @Environment(\.dependencies) private var dependencies
    @Environment(ClassGridScope.self) private var scope
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var store = CurriculumMapStore()
    @State private var model = ClassGridYearsModel()
    @AppStorage(UserDefaultsKeys.curriculumMapGranularity)
    private var granularityRaw = CurriculumGranularity.keyLessons.rawValue
    @State private var stateFilter: ChecklistDisplayStatus?
    @State private var rowTarget: ClassRow?
    @State private var cellTarget: CurriculumCellDetailTarget?
    @State private var draftToOpen: CDLessonAssignment?

    private var schoolYear: SchoolYearStore { dependencies.schoolYearStore }

    private var granularity: CurriculumGranularity {
        CurriculumGranularity(rawValue: granularityRaw) ?? .keyLessons
    }

    private var metrics: ClassGridYearsMetrics {
        #if os(macOS)
        .regular
        #else
        horizontalSizeClass == .regular ? .regular : .compact
        #endif
    }

    /// The states a row can be filtered to: the marks Three Years draws.
    static let filterStates: [ChecklistDisplayStatus] = [.notReady, .presented, .practicing, .reviewing, .mastered]

    var body: some View {
        VStack(spacing: 0) {
            content
            if metrics.isRegular {
                Divider()
                ClassGridYearsLegend()
            }
        }
        .toolbar { toolbar }
        .task {
            await store.load(from: viewContext)
            rebuild()
        }
        .task { await watchForChanges() }
        .onChange(of: store.loadedAt) { _, _ in rebuild() }
        .onChange(of: scope.area) { _, _ in rebuild() }
        .onChange(of: scope.childFilterIDs) { _, _ in rebuild() }
        .onChange(of: scope.searchText) { _, _ in rebuild() }
        .onChange(of: granularityRaw) { _, _ in rebuild() }
        .onChange(of: stateFilter) { _, _ in rebuild() }
        .onChange(of: schoolYear.startMonth) { _, _ in rebuild() }
        .onChange(of: schoolYear.startDay) { _, _ in rebuild() }
        .sheet(item: $rowTarget) { row in
            ClassCurriculumRowSheet(row: row, model: model, onPlan: plan(lessonID:students:)) { rowTarget = nil }
                .studentDetailSheetSizing()
        }
        .sheet(item: $cellTarget) { target in
            CurriculumCellDetailSheet(target: target, store: store) { cellTarget = nil }
                .studentDetailSheetSizing()
        }
        .sheet(item: $draftToOpen) { draft in
            PresentationDetailView(lessonAssignment: draft) { draftToOpen = nil }
                .studentDetailSheetSizing()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if metrics.isRegular {
            ToolbarItem(placement: .primaryAction) {
                rowsPicker
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .disabled(scope.area == nil)
                    .help(scope.area == nil
                          ? "Pick an area to see its lessons" : "Key lessons, or every lesson")
            }
        }
        ToolbarItem(placement: .primaryAction) { stateMenu }
    }

    private var rowsPicker: some View {
        Picker("Lessons shown", selection: $granularityRaw) {
            Text(CurriculumGranularity.keyLessons.label).tag(CurriculumGranularity.keyLessons.rawValue)
            Text(CurriculumGranularity.allLessons.label).tag(CurriculumGranularity.allLessons.rawValue)
        }
    }

    /// "Any state": only the rows with a child in one state. On the iPhone it also
    /// holds Key / All lessons.
    private var stateMenu: some View {
        Menu {
            Picker("Rows with a child", selection: $stateFilter) {
                Text("Any state").tag(ChecklistDisplayStatus?.none)
                ForEach(Self.filterStates, id: \.self) { state in
                    Text(Self.filterTitle(state)).tag(ChecklistDisplayStatus?.some(state))
                }
            }
            .pickerStyle(.inline)
            if !metrics.isRegular, scope.area != nil {
                rowsPicker.pickerStyle(.inline)
            }
        } label: {
            if metrics.isRegular {
                Label(
                    stateFilter.map(Self.filterTitle) ?? "Any state",
                    systemImage: "line.3.horizontal.decrease.circle"
                )
                    .labelStyle(.titleAndIcon)
            } else {
                Image(systemName: "line.3.horizontal.decrease.circle" + (stateFilter == nil ? "" : ".fill"))
            }
        }
        .help("Show only the rows with a child in one state")
        .accessibilityLabel("Show rows with a child in a given state")
    }

    static func filterTitle(_ state: ChecklistDisplayStatus) -> String {
        state == .notReady ? "Not yet" : state.label
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if store.isLoading, model.rows.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.columns.isEmpty {
            ContentUnavailableView(
                "No children to show", systemImage: "person.3",
                description: Text(scope.childFilterIDs.isEmpty
                    ? "Enroll a child to see the class here."
                    : "None of the children picked is enrolled.")
            )
        } else if model.rows.isEmpty {
            ContentUnavailableView(
                "Nothing to show",
                systemImage: "square.grid.3x3",
                description: Text("No row matches. Try another area, state or search.")
            )
        } else {
            ClassGridYearsGrid(
                model: model,
                areaTitle: scope.area,
                metrics: metrics,
                onRow: { rowTarget = $0 },
                onCell: { row, column in
                    cellTarget = CurriculumCellDetailTarget(
                        studentID: column.student.id, studentName: column.student.fullName,
                        title: row.title, lessonIDs: row.lessonIDs, range: nil, rangeLabel: nil
                    )
                }
            )
        }
    }

    // MARK: - Actions

    private func rebuild() {
        model.rebuild(
            store: store, area: scope.area, sequence: nil, granularity: granularity, stateFilter: stateFilter,
            startMonth: schoolYear.startMonth, startDay: schoolYear.startDay,
            childIDs: scope.childFilterIDs, query: scope.searchText
        )
    }

    /// The in-app twin of handing names to `schedule_presentation`: a draft
    /// presentation for the children who have not had the lesson, opened for
    /// the guide to schedule. Children already waiting for it stay on the plan
    /// they're on, and when they all are, that plan opens instead of a second
    /// draft (bug hunt 2026-10-12, #32).
    private func plan(lessonID: UUID, students: [CurriculumStudentRef]) {
        guard let lesson = viewContext.object(CDLesson.self, id: lessonID) else { return }
        let cdStudents = students.compactMap { viewContext.object(CDStudent.self, id: $0.id) }
        guard !cdStudents.isEmpty,
              let result = PresentationPlanner.planOrReuse(
                  lesson: lesson, students: cdStudents, purpose: nil, in: viewContext
              ) else { return }
        if result.isNew {
            result.plan.syncSnapshotsFromRelationships()
            saveCoordinator.save(viewContext, reason: "Draft presentation from the Class Grid's Three Years")
        }
        rowTarget = nil
        draftToOpen = result.plan
    }

    private func watchForChanges() async {
        let saves = NotificationCenter.default
            .notifications(named: NSManagedObjectContext.didSaveObjectIDsNotification)
            .map { CurriculumMapStore.watchedEntities(in: $0) }
        for await names in saves where !names.isEmpty {
            store.scheduleReload(from: viewContext)
        }
    }
}
