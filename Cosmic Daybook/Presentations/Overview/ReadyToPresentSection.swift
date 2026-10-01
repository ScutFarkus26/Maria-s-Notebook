// ReadyToPresentSection.swift
// The Presentations half of the Lessons & Work workspace: a state control over
// the backlog of lessons to give.
//
// The control is `ReadyToPresentFilterBar` — Ready, Brewing and Follow Up as
// segments, Overdue, Missed and Suggest as flags on Ready. The backlog under it
// is one compact row per lesson, ordered so the lesson serving the child who
// has waited longest comes first (`ReadyBacklog`); the rows themselves are
// built in `ReadyToPresentSection+Rows.swift`, the Follow Up state in
// `+FollowUp`, Suggest in `+Suggested`.

import SwiftUI
import CoreData

struct ReadyToPresentSection: View {
    // Not private: the extensions in their own files read it.
    @Environment(\.managedObjectContext) var viewContext
    @Environment(SaveCoordinator.self) var saveCoordinator
    @Environment(\.dependencies) var dependencies
    #if os(iOS)
    // Not private, for the same reason: the rows stack on a compact width.
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif

    let viewModel: PresentationsViewModel
    let blockingResults: [UUID: BlockingAlgorithmEngine.BlockingCheckResult]
    let getBlockingWork: (CDLessonAssignment) -> [UUID: CDWorkModel]
    let coordinator: PresentationsCoordinator
    let filterState: PresentationsFilterState
    /// The one row to ring and scroll to: a deep link's target. Nil the rest
    /// of the time — nothing on this screen highlights a row on its own.
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

    /// Held here rather than on each row so one pane has one dialog: it keeps
    /// the right count, and survives the row scrolling out from under it.
    @State var pendingDeletion: [CDLessonAssignment] = []

    /// The Lesson Age settings the Waiting Longest rail colors itself by, read
    /// once for the whole list. A child at or past its overdue threshold gets
    /// a tinted chip, so the chips and the rail agree about who is waiting.
    var ageSettings = StudentAgePaletteReader(.lessons)

    /// The lesson-title column, wide enough for most titles on two lines and
    /// scaled with the text so it keeps being.
    @ScaledMetric(relativeTo: .body) var titleColumnWidth: CGFloat = 200

    private struct FocusScrollTrigger: Equatable {
        let focusedID: UUID?
        let visibleIDs: [UUID]
    }

    var body: some View {
        // Computed once and handed to everything below, rather than each
        // count, row and trigger re-filtering and re-sorting the view model's
        // lists.
        let slices = makeSlices()
        // Everything a row could be selected from right now, so a selection
        // cannot outlive the state that revealed it.
        let selectableIDs = slices.visible(for: filterState.selectedChip).compactMap(\.id)
        let placement = focusPlacement(in: slices)
        VStack(alignment: .leading, spacing: 0) {
            ReadyToPresentFilterBar(selection: selectedChipBinding, count: slices.count)
            Divider()
            WorkspaceSelectionBar(selection: selection, noun: "presentation") {
                Button("Schedule Today") { scheduleSelectionToday() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            presentationsContent(slices, selectableIDs: selectableIDs)
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
        .task(id: placement) {
            reveal(placement, in: slices)
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
    private func presentationsContent(_ slices: ReadyToPresentSlices, selectableIDs: [UUID]) -> some View {
        // Follow-up rows are included: a deep link to a given presentation
        // lands on Follow Up, and it has to scroll there too.
        let trigger = FocusScrollTrigger(
            focusedID: focusedLessonID,
            visibleIDs: selectableIDs + followUpGroups.map(\.id)
        )
        ScrollViewReader { proxy in
            ScrollView {
                chipFilteredContent(slices)
                    .padding(.bottom, AppTheme.Spacing.medium + AppTheme.Spacing.xsmall)
            }
            .task(id: trigger) {
                guard let id = focusedLessonID,
                      trigger.visibleIDs.contains(id) else { return }
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
    private func chipFilteredContent(_ slices: ReadyToPresentSlices) -> some View {
        switch filterState.selectedChip {
        case .ready:
            if slices.ready.isEmpty {
                readyEmptyState(brewingCount: slices.blocked.count)
            } else {
                backlogList(slices.ready, state: .ready, slices: slices)
            }
        case .followUp:
            followUpContent
        case .waitingForWork:
            if slices.blocked.isEmpty {
                emptyState(
                    "Nothing Brewing", systemImage: "hourglass",
                    description: "No lessons are waiting on the children's work right now."
                )
            } else {
                backlogList(slices.blocked, state: .waitingForWork, slices: slices)
            }
        case .suggestedNext:
            suggestedNextContent(slices)
        case .overdue:
            flagContent(
                slices.overdue, flag: .overdue, slices: slices,
                explanation: "Ready lessons that have waited here more than 14 school days.",
                empty: ("Nothing Overdue", "All ready lessons are within the 14-school-day window.")
            )
        case .recentlyMissed:
            flagContent(
                slices.recentlyMissed, flag: .recentlyMissed, slices: slices,
                explanation: "Scheduled in the last 14 days but not given, because a child was absent. "
                    + "Drag one onto a day to give it again.",
                empty: ("No Missed Lessons", "No scheduled lessons were missed in the last 14 days.")
            )
        }
    }

    @ViewBuilder
    private func flagContent(
        _ lessons: [CDLessonAssignment],
        flag: PresentationsFilterChip,
        slices: ReadyToPresentSlices,
        explanation: String,
        empty: (title: String, description: String)
    ) -> some View {
        if lessons.isEmpty {
            emptyState(empty.title, systemImage: flag.systemImage, description: empty.description)
        } else {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
                stateExplanation(explanation)
                backlogList(lessons, state: flag, slices: slices)
            }
        }
    }

    /// The sentence under a flag saying what put these rows here — the one
    /// thing a flag's name alone does not.
    func stateExplanation(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, AppTheme.Spacing.medium)
            .padding(.top, AppTheme.Spacing.small)
    }

    @ViewBuilder
    private func readyEmptyState(brewingCount: Int) -> some View {
        if brewingCount == 0 {
            emptyState(
                "All Caught Up", systemImage: "checkmark.circle",
                description: "No lessons are waiting to be presented."
            )
        } else {
            emptyState(
                "Nothing Ready", systemImage: "hourglass",
                description: "Every planned lesson is brewing on the children's work. See Brewing."
            )
        }
    }

    func emptyState(_ title: String, systemImage: String, description: String) -> some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(description))
            .padding(.top, AppTheme.Spacing.large + AppTheme.Spacing.medium)
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
}
