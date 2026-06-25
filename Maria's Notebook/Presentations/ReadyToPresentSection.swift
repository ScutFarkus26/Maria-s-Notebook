// ReadyToPresentSection.swift
// Top-of-screen working area for the Presentations planner:
// chip row + prioritized inbox grid + the "On Deck (Waiting for Work)" rail.
//
// Phase 2: chips render with placeholder counts and selecting a chip does not
// yet narrow the grid. The slicing predicates are wired in Phase 3.

import SwiftUI
import CoreData
import OSLog

struct ReadyToPresentSection: View {
    private static let logger = Logger.presentations

    let viewModel: PresentationsViewModel
    let blockingResults: [UUID: BlockingAlgorithmEngine.BlockingCheckResult]
    let getBlockingWork: (CDLessonAssignment) -> [UUID: CDWorkModel]
    let filteredSnapshot: (CDLessonAssignment) -> LessonAssignmentSnapshot
    let coordinator: PresentationsCoordinator
    let filterState: PresentationsFilterState
    let suggestedLessonID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            chipRow
            Divider()
            presentationsContent
        }
    }

    // MARK: - Chip row

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.verySmall) {
                ForEach(PresentationsFilterChip.allCases) { chip in
                    chipButton(chip)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.medium)
            .padding(.vertical, AppTheme.Spacing.small)
        }
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
            .onChange(of: suggestedLessonID) {
                if let id = suggestedLessonID {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
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
        case .waitingForWork:
            singleSliceSection(
                filteredAndSortedBlockedLessons,
                emptyTitle: "Nothing brewing",
                emptySymbol: "hourglass",
                emptyDescription: "No lessons are waiting on student work right now."
            )
        case .suggestedNext:
            singleSliceSection(
                suggestedNextSlice,
                emptyTitle: "No suggestions",
                emptySymbol: "sparkles",
                emptyDescription: "No ready presentations match the current filters."
            )
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

    private var filteredAndSortedReadyLessons: [CDLessonAssignment] {
        viewModel.filteredAndSortedReady(
            studentFilter: coordinator.selectedStudentFilter,
            debouncedSearch: filterState.debouncedSearchText,
            committedFilters: filterState.committedFilters,
            hideStudentsScheduledToday: filterState.hideStudentsScheduledToday
        )
    }

    private var filteredAndSortedBlockedLessons: [CDLessonAssignment] {
        viewModel.filteredAndSortedBlocked(
            studentFilter: coordinator.selectedStudentFilter,
            debouncedSearch: filterState.debouncedSearchText,
            committedFilters: filterState.committedFilters,
            hideStudentsScheduledToday: filterState.hideStudentsScheduledToday
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

    private func readyGridItem(_ la: CDLessonAssignment) -> some View {
        let isSuggested: Bool = suggestedLessonID == la.id
        return inboxRow(la)
            .id(la.id)
            .overlay(
                RoundedRectangle(
                    cornerRadius: UIConstants.CornerRadius.medium,
                    style: .continuous
                )
                .stroke(Color.accentColor, lineWidth: isSuggested ? 2.5 : 0)
                .shadow(
                    color: .accentColor.opacity(isSuggested ? 0.4 : 0),
                    radius: 6
                )
            )
    }

}

// MARK: - Chip button + per-chip slice computations

extension ReadyToPresentSection {

    fileprivate func chipButton(_ chip: PresentationsFilterChip) -> some View {
        let isSelected = filterState.selectedChip == chip
        let accent = chip.accent
        let count = chipCount(chip)
        return Button {
            adaptiveWithAnimation(.easeInOut(duration: 0.15)) {
                filterState.selectedChip = isSelected ? .all : chip
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.xxsmall) {
                Image(systemName: chip.systemImage)
                    .font(.caption2)
                Text(chip.title)
                    .font(.caption.weight(.medium))
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(
                                isSelected
                                    ? Color.white.opacity(0.25)
                                    : accent.opacity(UIConstants.OpacityConstants.accent)
                            )
                        )
                }
            }
            .foregroundStyle(isSelected ? Color.white : accent)
            .padding(.horizontal, AppTheme.Spacing.small + AppTheme.Spacing.xxsmall)
            .padding(.vertical, AppTheme.Spacing.verySmall)
            .background(
                Capsule().fill(isSelected
                    ? accent
                    : accent.opacity(UIConstants.OpacityConstants.accent)))
        }
        .buttonStyle(.plain)
    }

    fileprivate func chipCount(_ chip: PresentationsFilterChip) -> Int {
        switch chip {
        case .all:
            return filteredAndSortedReadyLessons.count + filteredAndSortedBlockedLessons.count
        case .suggestedNext:
            return suggestedNextSlice.count
        case .waitingForWork:
            return filteredAndSortedBlockedLessons.count
        case .overdue:
            return overdueSlice.count
        case .recentlyMissed:
            return recentlyMissedSlice.count
        }
    }

    fileprivate var suggestedNextSlice: [CDLessonAssignment] {
        viewModel.suggestedNextLessons(
            among: filteredAndSortedReadyLessons,
            allLessonAssignments: viewModel.cachedLessonAssignments,
            limit: 3
        )
    }

    fileprivate var overdueSlice: [CDLessonAssignment] {
        viewModel.applyStudentAndTextFilters(
            to: viewModel.overdueReady(thresholdSchoolDays: 14),
            studentFilter: coordinator.selectedStudentFilter,
            debouncedSearch: filterState.debouncedSearchText,
            committedFilters: filterState.committedFilters,
            hideStudentsScheduledToday: filterState.hideStudentsScheduledToday
        )
    }

    fileprivate var recentlyMissedSlice: [CDLessonAssignment] {
        viewModel.applyStudentAndTextFilters(
            to: viewModel.recentlyMissed(within: 14),
            studentFilter: coordinator.selectedStudentFilter,
            debouncedSearch: filterState.debouncedSearchText,
            committedFilters: filterState.committedFilters,
            hideStudentsScheduledToday: filterState.hideStudentsScheduledToday
        )
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
        .contextMenu {
            Button("Unlock Lesson", systemImage: "lock.open") {
                unlockOnDeckLesson(la)
            }
            .disabled(la.manuallyUnblocked)
        }
    }

    @ViewBuilder
    fileprivate func inboxRow(
        _ la: CDLessonAssignment,
        blockingWork: [UUID: CDWorkModel] = [:],
        readyCount: Int? = nil,
        totalCount: Int? = nil
    ) -> some View {
        PresentationPlannerCard(
            snapshot: filteredSnapshot(la),
            day: nil,
            cachedLessons: viewModel.lessons,
            cachedStudents: viewModel.cachedStudents,
            blockingWork: blockingWork,
            doubleBookedStudentIDs: [],
            readyCount: readyCount,
            totalCount: totalCount
        )
        .onTapGesture { coordinator.showLessonAssignmentDetail(la) }
        .onDrag {
            let provider = NSItemProvider(object: NSString(string: (la.id ?? UUID()).uuidString))
            provider.suggestedName = viewModel.lessonsByID[uuidString: la.lessonID]?.name ?? "Lesson"
            return provider
        }
    }

    fileprivate func unlockOnDeckLesson(_ la: CDLessonAssignment) {
        guard !la.manuallyUnblocked, let ctx = la.managedObjectContext else { return }
        la.manuallyUnblocked = true
        la.modifiedAt = Date()
        do {
            try ctx.save()
        } catch {
            Self.logger.error("Failed to save manual unlock: \(error)")
        }
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
        do {
            try ctx.save()
        } catch {
            Self.logger.error("Failed to save after split: \(error)")
        }
    }
}
