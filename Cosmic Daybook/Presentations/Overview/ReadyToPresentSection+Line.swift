// ReadyToPresentSection+Line.swift
// What makes a backlog line a presentation rather than a picture of one: it
// drags onto the calendar, opens on a tap, joins a selection on a command-
// click, carries the presentation's context menu, and can be ringed and
// scrolled to by a deep link.
//
// Every line — a single-group row, or one group of a lesson with several —
// goes through `backlogLine`, so the two shapes cannot drift apart on any of
// that.

import CoreData
import SwiftUI

extension ReadyToPresentSection {

    // swiftlint:disable:next function_parameter_count
    func backlogLine<Content: View>(
        _ la: CDLessonAssignment,
        chips: [BacklogChip],
        groupLabel: String?,
        groupCount: Int,
        context: BacklogRenderContext,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isFocused = focusedLessonID != nil && focusedLessonID == la.id
        let readiness = partialReadiness(of: la, context: context)
        let line = content()
            .padding(.horizontal, AppTheme.Spacing.small)
            .padding(.vertical, AppTheme.Spacing.verySmall)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .hoverableRow(cornerRadius: UIConstants.CornerRadius.medium)
            // Command-click extends the selection instead of opening the
            // line, so one click never both selects and navigates away.
            .onTapGesture {
                guard !selection.handleTap(on: la.id) else { return }
                coordinator.showLessonAssignmentDetail(la)
            }
            // One element per line, read as "Lesson, children, flags"; the
            // Move Ready button inside it becomes a named action.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(for: la, chips: chips, groupLabel: groupLabel, context: context))
            .accessibilityAddTraits(.isButton)
            .accessibilityActions {
                if let readiness {
                    Button("Move Ready") { splitReadyToInbox(la, result: readiness.result) }
                }
            }
        return draggableLine(line, la: la, chips: chips)
            .id(la.id ?? UUID())
            .focusHighlight(isFocused)
            .workspaceSelectionRing(
                selection.contains(la.id),
                cornerRadius: UIConstants.CornerRadius.medium
            )
            .contextMenu {
                lessonMenuItems(for: la)
                if groupCount > 1 {
                    Button("Merge Groups…", systemImage: "arrow.triangle.merge") {
                        coordinator.showMergeGroups(forLesson: la.resolvedLessonID)
                    }
                }
                if context.state == .waitingForWork {
                    Button("Unlock Lesson", systemImage: "lock.open") {
                        unlockBrewingLesson(la)
                    }
                    .disabled(la.manuallyUnblocked)
                }
                Divider()
                deleteButton(for: la)
            }
    }

    /// A line with no id cannot be resolved by any drop handler, and the drop
    /// would report success while doing nothing — so it simply isn't a drag
    /// source.
    @ViewBuilder
    private func draggableLine(_ line: some View, la: CDLessonAssignment, chips: [BacklogChip]) -> some View {
        if let id = la.id {
            line.draggable(
                selection.dragPayload(startingAt: id, make: UnifiedCalendarDragPayload.presentation)
            ) {
                dragPreview(for: la, names: chips.map(\.name))
            }
        } else {
            line
        }
    }

    /// Drag previews render detached from the app's environment, so anything
    /// the preview could read has to be re-injected — a preview whose
    /// `@FetchRequest`s have no context is a crash at drag lift.
    private func dragPreview(for la: CDLessonAssignment, names: [String]) -> some View {
        BacklogDragPreview(
            title: viewModel.lessonTitle(for: la),
            areaColor: areaColor(for: la),
            names: names
        )
        .environment(\.managedObjectContext, viewContext)
    }

    private func accessibilityLabel(
        for la: CDLessonAssignment,
        chips: [BacklogChip],
        groupLabel: String?,
        context: BacklogRenderContext
    ) -> String {
        var parts = [viewModel.lessonTitle(for: la)]
        if let groupLabel { parts.append(groupLabel) }
        parts.append(chips.isEmpty ? "no children" : chips.map(\.accessibilityText).joined(separator: ", "))
        if let id = la.id {
            if context.overdueIDs.contains(id) { parts.append("overdue") }
            if context.missedIDs.contains(id) { parts.append("missed") }
        }
        if let readiness = partialReadiness(of: la, context: context) {
            parts.append("\(readiness.ready) of \(readiness.total) ready")
        }
        return parts.joined(separator: ", ")
    }
}
