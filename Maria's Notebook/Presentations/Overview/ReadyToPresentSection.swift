// ReadyToPresentSection.swift
// The Presentations half of the Lessons & Work workspace: a pill row over the
// prioritized inbox of lessons to give.
//
// The pill row is `WorkspaceFilterPillRow`, the same component the Work half
// uses, so both halves of one screen are filtered by one mechanism at one
// level. The Follow Up pill and the groups behind it live in
// `ReadyToPresentSection+FollowUp.swift`.

import SwiftUI
import CoreData

struct ReadyToPresentSection: View {
    // Not private: the Follow Up extension in its own file reads it.
    @Environment(\.managedObjectContext) var viewContext

    let viewModel: PresentationsViewModel
    let blockingResults: [UUID: BlockingAlgorithmEngine.BlockingCheckResult]
    let getBlockingWork: (CDLessonAssignment) -> [UUID: CDWorkModel]
    let filteredSnapshot: (CDLessonAssignment) -> LessonAssignmentSnapshot
    let coordinator: PresentationsCoordinator
    let filterState: PresentationsFilterState
    /// The one card to ring and scroll to: a deep link's target. Nil the rest
    /// of the time — nothing on this screen highlights a card on its own.
    let focusedLessonID: UUID?
    /// Command-click selection, shared with the workspace so a selection
    /// survives a trip to the calendar and back.
    let selection: WorkspaceMultiSelection

    /// Presentations already given that still carry an unresolved follow-up.
    /// Grouped into `followUpGroups` on a change-keyed task rather than in a
    /// `body` pass — the service dictionary-builds over every assignment,
    /// lesson and student each time it runs.
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDLessonPresentation.presentedAt, ascending: true)],
        predicate: NSPredicate(format: "followUpActionRaw != nil AND followUpResolvedAt == nil"),
        animation: .default
    ) var followUpRows: FetchedResults<CDLessonPresentation>

    @State var followUpGroups: [FollowingPresentationGroup] = []

    /// Held here rather than on each card so one pane has one dialog: it keeps
    /// the right count, and survives the card scrolling out from under it.
    @State var pendingDeletion: [CDLessonAssignment] = []

    private struct FocusScrollTrigger: Equatable {
        let focusedID: UUID?
        let visibleIDs: [UUID]
    }

    private var focusScrollTrigger: FocusScrollTrigger {
        FocusScrollTrigger(
            focusedID: focusedLessonID,
            // Follow-up rows are included: a deep link to a given presentation
            // lands on the Follow Up pill, and it has to scroll there too.
            visibleIDs: (filteredAndSortedBlockedLessons + filteredAndSortedReadyLessons)
                .compactMap(\.id) + followUpGroups.map(\.id)
        )
    }

    /// Everything a card could be selected from right now, so a selection
    /// cannot outlive the pill that revealed it.
    private var selectableIDs: [UUID] {
        (filteredAndSortedBlockedLessons + filteredAndSortedReadyLessons).compactMap(\.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WorkspaceFilterPillRow(
                selection: selectedChipBinding,
                unfiltered: .all,
                count: chipCount
            )
            Divider()
            WorkspaceSelectionBar(selection: selection, noun: "presentation") {
                Button("Schedule Today") { scheduleSelectionToday() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            presentationsContent
        }
        .workspaceDeletionConfirmation(
            pending: $pendingDeletion,
            title: deletionTitle,
            confirmTitle: deletionConfirmTitle,
            message: deletionMessage,
            onConfirm: performPendingDeletion
        )
        .task(id: followUpTrigger) {
            rebuildFollowUpGroups()
        }
        .task(id: selectableIDs) {
            selection.retain(Set(selectableIDs))
        }
    }

    private var selectedChipBinding: Binding<PresentationsFilterChip> {
        Binding(
            get: { filterState.selectedChip },
            set: { filterState.selectedChip = $0 }
        )
    }

    // MARK: - Content

    @ViewBuilder
    private var presentationsContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    chipFilteredContent
                }
                .padding(.bottom, AppTheme.Spacing.medium + AppTheme.Spacing.xsmall)
            }
            .task(id: focusScrollTrigger) {
                guard let id = focusedLessonID,
                      focusScrollTrigger.visibleIDs.contains(id) else { return }
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private var chipFilteredContent: some View {
        switch filterState.selectedChip {
        case .all:
            blockedSection
            readySection
        case .followUp:
            followUpContent
        case .waitingForWork:
            singleSliceSection(
                filteredAndSortedBlockedLessons,
                emptyTitle: "Nothing brewing",
                emptySymbol: "hourglass",
                emptyDescription: "No lessons are waiting on student work right now."
            )
        case .suggestedNext:
            suggestedNextContent
        case .overdue:
            singleSliceSection(
                overdueSlice,
                emptyTitle: "Nothing overdue",
                emptySymbol: "clock",
                emptyDescription: "All ready lessons are within the 14-school-day window."
            )
        case .recentlyMissed:
            singleSliceSection(
                recentlyMissedSlice,
                emptyTitle: "No missed lessons",
                emptySymbol: "person",
                emptyDescription: "No scheduled lessons were missed in the last 14 days."
            )
        }
    }

    @ViewBuilder
    private func singleSliceSection(
        _ lessons: [CDLessonAssignment],
        emptyTitle: String,
        emptySymbol: String,
        emptyDescription: String
    ) -> some View {
        if lessons.isEmpty {
            ContentUnavailableView(
                emptyTitle, systemImage: emptySymbol,
                description: Text(emptyDescription)
            )
            .padding(.top, AppTheme.Spacing.large + AppTheme.Spacing.medium)
        } else {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: AppTheme.Spacing.small),
                GridItem(.flexible(), spacing: AppTheme.Spacing.small),
                GridItem(.flexible(), spacing: AppTheme.Spacing.small)
            ], alignment: .leading, spacing: AppTheme.Spacing.small) {
                ForEach(lessons, id: \.id) { la in
                    readyGridItem(la)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.compact)
        }
    }

    // MARK: - Filtered slices (delegates to PresentationsViewModel)

    var filteredAndSortedReadyLessons: [CDLessonAssignment] {
        viewModel.filteredAndSortedReady(
            studentFilter: coordinator.selectedStudentFilter,
            debouncedSearch: filterState.debouncedSearchText
        )
    }

    var filteredAndSortedBlockedLessons: [CDLessonAssignment] {
        viewModel.filteredAndSortedBlocked(
            studentFilter: coordinator.selectedStudentFilter,
            debouncedSearch: filterState.debouncedSearchText
        )
    }

    @ViewBuilder
    private var blockedSection: some View {
        if !filteredAndSortedBlockedLessons.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                Label("Brewing", systemImage: "hourglass")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppTheme.Spacing.compact)

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: AppTheme.Spacing.small),
                    GridItem(.flexible(), spacing: AppTheme.Spacing.small),
                    GridItem(.flexible(), spacing: AppTheme.Spacing.small)
                ], alignment: .leading, spacing: AppTheme.Spacing.small) {
                    ForEach(filteredAndSortedBlockedLessons, id: \.id) { la in
                        onDeckCard(la, blockingWork: getBlockingWork(la))
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.compact)
            }
            .padding(.top, AppTheme.Spacing.compact)
        }
    }

    @ViewBuilder
    private var readySection: some View {
        if filteredAndSortedReadyLessons.isEmpty {
            if filteredAndSortedBlockedLessons.isEmpty {
                ContentUnavailableView(
                    "All Caught Up", systemImage: "checkmark.circle",
                    description: Text("No unscheduled presentations.")
                )
                    .padding(.top, AppTheme.Spacing.large + AppTheme.Spacing.medium)
            } else {
                Text("All planned presentations are brewing.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, AppTheme.Spacing.medium + AppTheme.Spacing.xsmall)
            }
        } else {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                Label("Ready", systemImage: "checkmark.circle")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppTheme.Spacing.compact)
                readyGrid
            }
            .padding(.top, filteredAndSortedBlockedLessons.isEmpty
                      ? AppTheme.Spacing.compact
                      : AppTheme.Spacing.medium + AppTheme.Spacing.small)
        }
    }

    private var readyGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: AppTheme.Spacing.small),
            GridItem(.flexible(), spacing: AppTheme.Spacing.small),
            GridItem(.flexible(), spacing: AppTheme.Spacing.small)
        ], alignment: .leading, spacing: AppTheme.Spacing.small) {
            ForEach(filteredAndSortedReadyLessons, id: \.id) { la in
                readyGridItem(la)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.compact)
    }

    func readyGridItem(_ la: CDLessonAssignment) -> some View {
        let isFocused = focusedLessonID != nil && focusedLessonID == la.id
        return inboxRow(la)
            .id(la.id ?? UUID())
            .focusHighlight(isFocused)
            .workspaceSelectionRing(
                selection.contains(la.id),
                cornerRadius: UIConstants.CornerRadius.medium
            )
            .contextMenu {
                ShowInChecklistButton(lessonID: la.resolvedLessonID, context: viewContext)
                Divider()
                deleteButton(for: la)
            }
    }

}

// MARK: - Cards + On Deck actions

extension ReadyToPresentSection {

    @ViewBuilder
    fileprivate func onDeckCard(_ la: CDLessonAssignment, blockingWork: [UUID: CDWorkModel]) -> some View {
        let result = la.id.flatMap { blockingResults[$0] }
        let readyCount = result?.readyStudentIDs.count ?? 0
        let totalCount = la.resolvedStudentIDs.count
        let hasPartialReadiness = readyCount > 0 && readyCount < totalCount
        let isFocused = focusedLessonID != nil && focusedLessonID == la.id

        VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
            // The card now owns the progress bar + "X of Y ready" label in its footer.
            inboxRow(
                la,
                blockingWork: blockingWork,
                readyCount: readyCount,
                totalCount: totalCount
            )

            // "Move Ready" is an action, not a status display — stays external.
            if hasPartialReadiness, let result {
                HStack {
                    Spacer()
                    Button {
                        splitReadyToInbox(la, result: result)
                    } label: {
                        Text("Move Ready")
                            .font(.caption2.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(.horizontal, AppTheme.Spacing.verySmall)
            }
        }
        .id(la.id ?? UUID())
        .focusHighlight(isFocused)
        .workspaceSelectionRing(
            selection.contains(la.id),
            cornerRadius: UIConstants.CornerRadius.medium
        )
        .contextMenu {
            ShowInChecklistButton(lessonID: la.resolvedLessonID, context: viewContext)
            Button("Unlock Lesson", systemImage: "lock.open") {
                unlockOnDeckLesson(la)
            }
            .disabled(la.manuallyUnblocked)
            Divider()
            deleteButton(for: la)
        }
    }

    @ViewBuilder
    fileprivate func inboxRow(
        _ la: CDLessonAssignment,
        blockingWork: [UUID: CDWorkModel] = [:],
        readyCount: Int? = nil,
        totalCount: Int? = nil
    ) -> some View {
        let card = PresentationPlannerCard(
            snapshot: filteredSnapshot(la),
            day: nil,
            cachedLessons: viewModel.lessons,
            cachedStudents: viewModel.cachedStudents,
            blockingWork: blockingWork,
            doubleBookedStudentIDs: [],
            readyCount: readyCount,
            totalCount: totalCount
        )
        // Command-click extends the selection instead of opening the card, so
        // one click never both selects and navigates away.
        .onTapGesture {
            guard !selection.handleTap(on: la.id) else { return }
            coordinator.showLessonAssignmentDetail(la)
        }

        // A row with no id cannot be resolved by any drop handler, and the drop
        // would report success while doing nothing — so it simply isn't a drag
        // source.
        if let id = la.id {
            card.draggable(
                selection.dragPayload(startingAt: id, make: UnifiedCalendarDragPayload.presentation)
            ) {
                dragPreview(for: la)
            }
        } else {
            card
        }
    }

    /// Drag previews render detached from the app's environment, so anything
    /// the preview reads has to be re-injected — a card whose `@FetchRequest`s
    /// have no context is a crash at drag lift.
    fileprivate func dragPreview(for la: CDLessonAssignment) -> some View {
        PresentationPlannerCard(
            snapshot: filteredSnapshot(la),
            day: nil,
            cachedLessons: [],
            cachedStudents: [],
            blockingWork: [:],
            doubleBookedStudentIDs: []
        )
        .opacity(UIConstants.OpacityConstants.nearSolid)
        .environment(\.managedObjectContext, viewContext)
    }

    /// Puts every selected presentation on today, spaced the way a drop onto
    /// today's column would space them.
    fileprivate func scheduleSelectionToday() {
        let selected = (filteredAndSortedReadyLessons + filteredAndSortedBlockedLessons)
            .filter { selection.contains($0.id) }
        guard !selected.isEmpty else { return }

        let startOfDay = AppCalendar.startOfDay(Date())
        let base = AppCalendar.shared.date(byAdding: .hour, value: 9, to: startOfDay) ?? startOfDay
        for (index, assignment) in selected.enumerated() {
            let offset = Double(index * UIConstants.scheduleSpacingSeconds)
            assignment.setScheduledFor(base.addingTimeInterval(offset), using: AppCalendar.shared)
        }
        if viewContext.safeSave() {
            selection.clear()
        }
    }

    fileprivate func unlockOnDeckLesson(_ la: CDLessonAssignment) {
        guard !la.manuallyUnblocked, let ctx = la.managedObjectContext else { return }
        la.manuallyUnblocked = true
        la.modifiedAt = Date()
        ctx.safeSave()
    }

    fileprivate func splitReadyToInbox(_ la: CDLessonAssignment, result: BlockingAlgorithmEngine.BlockingCheckResult) {
        let readyIDs = result.readyStudentIDs
        guard !readyIDs.isEmpty else { return }

        guard let ctx = la.managedObjectContext else { return }
        PresentationSplitService.splitReadyStudents(
            from: la,
            readyStudentIDs: readyIDs,
            asDraft: true,
            context: ctx
        )
        ctx.safeSave()
    }
}
