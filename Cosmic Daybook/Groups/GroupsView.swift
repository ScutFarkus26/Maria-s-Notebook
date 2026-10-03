//
//  GroupsView.swift
//  Cosmic Daybook
//
//  The Groups page: which children can be taught together, lesson by
//  lesson. It replaces the Group Planner (GROUPS_PAGE_PLAN.md).
//
//  The page owns a `ReadyQueueLoader` of its own, the one Today runs: the
//  same queue, read off the main thread, rebuilt only while the page can be
//  seen and only when one of the queue's inputs moved. `ReadyGroups` folds
//  it onto lessons; a card is 2+ ready children, and the lessons with one
//  ready child fold into one row below the cards. Lessons only held children
//  wait on are left out here (Today lists them).
//

import CoreData
import SwiftUI

struct GroupsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies
    /// Made once, when the page first appears (as `TodayRootView` makes Today's).
    @State private var loader: ReadyQueueLoader?

    /// Its own stack, so the title shows and the breadcrumbs can push; behind
    /// the iPhone's More tab it pushes into that stack instead.
    var body: some View {
        PageNavigationStack {
            if let loader {
                GroupsPage(loader: loader)
            } else {
                Color.clear
                    .onAppear {
                        guard loader == nil else { return }
                        let made = ReadyQueueLoader(context: viewContext)
                        made.lessonCatalog = dependencies.lessonCatalog
                        loader = made
                    }
            }
        }
    }
}

/// The page itself, once its loader exists.
private struct GroupsPage: View {
    let loader: ReadyQueueLoader

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies
    @Environment(SaveCoordinator.self) private var saveCoordinator
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private var ageSettings = StudentAgePaletteReader(.lessons)

    @State private var levelFilter: LevelFilter = .all
    @State private var selectedArea: String?
    @State private var singlesExpanded = false
    @State private var lessonToPlan: ReadyLessonPlan?
    /// The cards, rebuilt when the loader publishes or the level changes.
    @State private var built: ReadyGroups?

    init(loader: ReadyQueueLoader) {
        self.loader = loader
    }

    /// What `built` was made from.
    private struct BuildKey: Equatable {
        let version: Int
        let level: LevelFilter
    }

    var body: some View {
        content
            .navigationTitle("Groups")
            .toolbar { levelPicker }
            .navigationDestination(for: SequenceLadderRoute.self) { route in
                ladder(for: route)
            }
            .sheet(item: $lessonToPlan) { plan in
                ReadyLessonPlanSheet(plan: plan) { lessonToPlan = nil }
            }
            .modifier(ReadyQueueRefresh(loader: loader))
            .onChange(of: BuildKey(version: loader.publishCount, level: levelFilter), initial: true) {
                rebuildCards()
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let built {
            let visible = built.inArea(currentArea(in: built))
            if built.groups.isEmpty && built.singles.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        areaChips(built.areaCounts)
                        cards(visible.groups)
                        if visible.groups.isEmpty {
                            Text("No lesson has two children ready yet.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if !visible.singles.isEmpty {
                            SinglesRow(
                                singles: visible.singles,
                                palette: ageSettings.palette,
                                isExpanded: $singlesExpanded,
                                onPlan: plan
                            )
                        }
                    }
                    .padding()
                }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No One Is Ready Yet", systemImage: "person.3")
        } description: {
            Text("When a child is confirmed or mastered on a lesson, the next lesson in its sequence shows here, "
                + "with everyone else ready for it.")
        }
    }

    @ViewBuilder
    private func cards(_ groups: [LessonGroup]) -> some View {
        let palette = ageSettings.palette
        if usesGrid {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: 3),
                alignment: .leading,
                spacing: 16
            ) {
                ForEach(groups) { group in
                    card(group, palette: palette)
                }
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(groups) { group in
                    card(group, palette: palette)
                }
            }
        }
    }

    private func card(_ group: LessonGroup, palette: StudentAgePalette) -> some View {
        GroupCard(group: group, palette: palette, onPlan: { plan(group) }, onConfirm: confirm)
    }

    /// Three columns on the Mac and a regular-width iPad; a list on compact.
    private var usesGrid: Bool {
        #if os(iOS)
        horizontalSizeClass != .compact
        #else
        true
        #endif
    }

    // MARK: - Area Chips

    private func areaChips(_ counts: [ReadyGroups.AreaCount]) -> some View {
        let byArea = Dictionary(counts.map { ($0.area, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = FilterOrderStore.loadAreaOrder(existing: counts.map(\.area))
        let current = selectedArea
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                AreaChip(label: "All", isSelected: current == nil) { selectedArea = nil }
                ForEach(ordered, id: \.self) { area in
                    let count = byArea[area].map { $0.groups + $0.singles } ?? 0
                    AreaChip(label: "\(area) \(count)", isSelected: current == area) {
                        selectedArea = current == area ? nil : area
                    }
                    .accessibilityLabel("\(area), \(count) lessons")
                }
            }
        }
    }

    /// The selected area while it still has cards; nil (All) otherwise.
    private func currentArea(in built: ReadyGroups) -> String? {
        guard let selectedArea, built.areaCounts.contains(where: { $0.area == selectedArea }) else { return nil }
        return selectedArea
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var levelPicker: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Picker("Level", selection: $levelFilter) {
                ForEach(LevelFilter.allCases) { level in
                    Text(level.rawValue).tag(level)
                }
            }
            .pickerStyle(.menu)
        }
    }

    // MARK: - Ladder

    private func ladder(for route: SequenceLadderRoute) -> some View {
        SequenceLadderHost(loader: loader, route: route, levels: levels, schoolDaysSince: schoolDaysSince)
    }

    // MARK: - Building

    /// The level picker as the builders take it; nil keeps everyone.
    private var levels: Set<CDStudent.Level>? {
        levelFilter == .all ? nil : Set(CDStudent.Level.allCases.filter(levelFilter.matches))
    }

    private var schoolDaysSince: (Date) -> Int {
        let context = viewContext
        return { LessonAgeHelper.schoolDaysSinceCreation(createdAt: $0, using: context) }
    }

    private func rebuildCards() {
        guard let snapshot = loader.snapshot else {
            built = nil
            return
        }
        built = ReadyGroups.build(from: snapshot.filtered(levels: levels), schoolDaysSince: schoolDaysSince)
    }

    // MARK: - Actions

    private func plan(_ group: LessonGroup) {
        guard let lesson = dependencies.lessonCatalog.byID[group.lessonUUID] else { return }
        lessonToPlan = ReadyLessonPlan(lesson: lesson, readyStudentIDs: group.readyStudentUUIDs)
    }

    /// Confirms the child on the previous lesson, which moves her to Ready
    /// once the queue rebuilds.
    private func confirm(_ entry: LessonGroup.Unconfirmed) {
        guard let studentID = entry.child.uuid,
              let assignment = try? viewContext.existingObject(with: entry.assignmentID) as? CDLessonAssignment
        else { return }
        assignment.confirmStudent(studentID)
        saveCoordinator.save(viewContext, reason: "Confirm lesson")
    }
}

/// The ladder, reading the loader's latest snapshot itself and keeping it
/// fresh while it is the screen on top (the page under it stops refreshing
/// once covered), so a Confirm or an import shows without going back.
private struct SequenceLadderHost: View {
    let loader: ReadyQueueLoader
    let route: SequenceLadderRoute
    let levels: Set<CDStudent.Level>?
    let schoolDaysSince: (Date) -> Int

    var body: some View {
        Group {
            if let snapshot = loader.snapshot {
                SequenceLadderView(
                    area: route.area,
                    sequence: route.sequence,
                    snapshot: snapshot.filtered(levels: levels),
                    schoolDaysSince: schoolDaysSince
                )
            }
        }
        .modifier(ReadyQueueRefresh(loader: loader))
    }
}

/// Rebuilds the ready queue on appear, and after its inputs change while the
/// screen is visible, 300 ms after the last change: typing in another window
/// edits work rows on every keystroke, and each rebuild reads the whole
/// record off the main thread.
private struct ReadyQueueRefresh: ViewModifier {
    let loader: ReadyQueueLoader
    @Environment(\.managedObjectContext) private var viewContext
    @State private var pending: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onAppear { loader.refreshIfNeeded() }
            .onDisappear { pending?.cancel() }
            // Only while on screen: a TabView keeps the page alive behind the
            // others, and `.onAppear` above catches up when it returns.
            .onPresentationDataChangeWhenVisible(
                of: ReadyQueueLoader.inputEntities, in: viewContext, catchUpOnAppear: false
            ) {
                pending?.cancel()
                pending = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    loader.refreshIfNeeded()
                }
            }
    }
}

/// One area filter on the Groups page, at least 44 points tall on iOS.
private struct AreaChip: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(AppTheme.ScaledFont.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .capsuleFill(
                    isSelected
                        ? Color.accentColor.opacity(UIConstants.OpacityConstants.accent)
                        : Color.primary.opacity(UIConstants.OpacityConstants.veryFaint)
                )
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                #if os(iOS)
                .frame(minHeight: 44)
                #endif
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
