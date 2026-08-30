// LessonsAndWorkWorkView.swift
// The Work half of the Lessons & Work workspace.
//
// Children's work now reads the way presentations always did: a pill row of
// states over a grid of cards, with the Scheduled calendar pinned below to
// drag onto. Before this, work had no pill row at all — its states *were* the
// workspace's top-level tabs, so moving from "what I have to check" to "what I
// have to plan" meant leaving the Work list entirely and coming back through a
// second picker.
//
// The pills are `WorkFilterChip`, which is `TriageBucket` in the workspace's
// vocabulary. Nothing about where a work item belongs changed; only where the
// guide picks between the buckets did.

import CoreData
import SwiftUI

struct LessonsAndWorkWorkView: View {
    /// Every open work item, already triaged by the workspace.
    let split: TriageSplit<CDWorkModel>
    /// The ids that survive the search field and the kind chips. Slicing the
    /// partition against this keeps one filtering path for the whole half.
    let visibleWorkIDs: Set<UUID>
    let lessonsByID: [UUID: CDLesson]
    let studentsByID: [UUID: CDStudent]
    let attentionWorkIDs: Set<UUID>
    let sortMode: WorkAgendaSortMode
    let searchText: String
    let focusedWorkID: UUID?
    let selection: WorkspaceMultiSelection
    @Binding var chip: WorkFilterChip
    /// Which kinds of work to show — practice, research, and the rest. A
    /// different axis from the state pills, so it keeps its own row.
    @Binding var visibleKinds: Set<WorkKind>
    let onOpenWork: (CDWorkModel) -> Void
    let onMarkCompleted: (CDWorkModel) -> Void
    let onScheduleToday: (CDWorkModel) -> Void
    /// Re-triages the workspace after a deletion, so the pill counts and the
    /// pinned calendar drop the record in the same pass.
    let onDeleted: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceFilterPillRow(
                selection: $chip,
                unfiltered: .all,
                count: count(for:)
            )
            #if os(macOS)
            // On iPhone this rides in the workspace header instead, where the
            // search field already is.
            WorkKindFilterChipBar(visibleKinds: $visibleKinds)
                .padding(.top, -AppTheme.Spacing.verySmall)
            #endif
            Divider()
            WorkspaceSelectionBar(selection: selection, noun: "work item") {
                Button("Schedule Today") { applyToSelection(onScheduleToday) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Mark Completed") { applyToSelection(onMarkCompleted) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            content
        }
        .task(id: visibleIDsInSlice) {
            selection.retain(visibleIDsInSlice)
        }
    }

    @ViewBuilder
    private var content: some View {
        if slice.isEmpty {
            ContentUnavailableView(
                emptyTitle,
                systemImage: chip.systemImage,
                description: Text(emptyDescription)
            )
        } else {
            OpenWorkGrid(
                works: slice,
                lessonsByID: lessonsByID,
                studentsByID: studentsByID,
                attentionWorkIDs: attentionWorkIDs,
                sortMode: sortMode,
                focusedWorkID: focusedWorkID,
                selection: selection,
                onOpen: onOpenWork,
                onMarkCompleted: onMarkCompleted,
                onScheduleToday: onScheduleToday,
                onDeleted: onDeleted
            )
        }
    }

    // MARK: - Slices

    /// The work the chosen pill shows, narrowed to what the search and kind
    /// filters left visible.
    private var slice: [CDWorkModel] {
        works(in: chip)
    }

    private var visibleIDsInSlice: Set<UUID> {
        Set(slice.compactMap(\.id))
    }

    private func works(in chip: WorkFilterChip) -> [CDWorkModel] {
        chip.slice(of: split).filter { work in
            guard let id = work.id else { return false }
            return visibleWorkIDs.contains(id)
        }
    }

    private func count(for chip: WorkFilterChip) -> Int {
        works(in: chip).count
    }

    // MARK: - Bulk actions

    /// Runs a per-item action across the selection, then lets it go — the
    /// selected cards have either moved to another pill or left the list.
    private func applyToSelection(_ action: (CDWorkModel) -> Void) {
        for work in slice where selection.contains(work.id) {
            action(work)
        }
        selection.clear()
    }

    // MARK: - Empty states

    private var isSearching: Bool { !searchText.trimmed().isEmpty }

    private var emptyTitle: String {
        if isSearching { return "No Matching Work" }
        switch chip {
        case .all: return "No Open Work"
        case .needsChecking: return "Nothing to Check"
        case .toSchedule: return "Every Work Item Has a Day"
        case .scheduled: return "Nothing on the Calendar"
        }
    }

    private var emptyDescription: String {
        if isSearching { return "No work in this list matches this search." }
        switch chip {
        case .all: return "Finished work lives under Logs."
        case .needsChecking:
            return "No child's work is due, in review, or has gone quiet."
        case .toSchedule:
            return "Work with a due date or a scheduled check-in appears under Scheduled."
        case .scheduled:
            return "Drag work onto a day below to put it on the calendar."
        }
    }
}
