// ReadyToPresentSection+Rows.swift
// The backlog's rows: one per lesson, each presentation of it a line.
//
// A lesson planned for one group is one line — area dot, title, the children,
// the flags. A lesson planned for several is one row whose groups are listed
// under it, each still its own drag source, tap target, selection and context
// menu, with a "Merge Groups…" button that opens the merge sheet for just
// that lesson. Everything a row shows is resolved here from the view model's
// caches; nothing on a row fetches.

import CoreData
import SwiftUI

/// Values every row of one list reads, resolved once per render.
struct BacklogRenderContext {
    /// The state or flag the list is drawn under.
    let state: PresentationsFilterChip
    let overdueIDs: Set<UUID>
    let missedIDs: Set<UUID>
    let palette: StudentAgePalette
    let isCompact: Bool
}

/// How far a brewing presentation has come: some of its children are ready.
struct BacklogReadiness {
    let ready: Int
    let total: Int
    let result: BlockingAlgorithmEngine.BlockingCheckResult
}

extension ReadyToPresentSection {

    var isCompactWidth: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    func renderContext(state: PresentationsFilterChip, slices: ReadyToPresentSlices) -> BacklogRenderContext {
        BacklogRenderContext(
            state: state,
            overdueIDs: Set(slices.overdue.compactMap(\.id)),
            missedIDs: Set(slices.recentlyMissed.compactMap(\.id)),
            palette: ageSettings.palette,
            isCompact: isCompactWidth
        )
    }

    /// One list of rows. Brewing keeps its oldest-first order — nothing there
    /// can be given yet, so who is waiting does not choose among them; every
    /// other list puts the lesson serving the longest-waiting child first.
    ///
    /// A plain stack, not a lazy one: a deep link scrolls to a presentation's
    /// id, which sits on a line inside a lesson's row, and a lazy stack can
    /// only scroll to rows it has already built. A backlog is tens of rows.
    func backlogList(
        _ assignments: [CDLessonAssignment],
        state: PresentationsFilterChip,
        slices: ReadyToPresentSlices
    ) -> some View {
        let context = renderContext(state: state, slices: slices)
        let groups = ReadyBacklog.groupByLesson(
            assignments,
            lessonID: \.resolvedLessonID,
            studentIDs: \.resolvedStudentIDs,
            waits: viewModel.daysSinceLastLessonByStudent,
            longestWaitFirst: state != .waitingForWork
        )
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(groups) { group in
                lessonRow(group, context: context)
                Divider()
                    .padding(.leading, AppTheme.Spacing.small)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.small)
        .padding(.top, AppTheme.Spacing.xsmall)
    }

    @ViewBuilder
    private func lessonRow(
        _ group: BacklogLessonGroup<CDLessonAssignment>,
        context: BacklogRenderContext
    ) -> some View {
        if group.items.count == 1, let only = group.items.first {
            singleLessonRow(only, context: context)
        } else {
            multiGroupRow(group, context: context)
        }
    }

    /// A lesson with one group: the whole row is the line.
    func singleLessonRow(_ la: CDLessonAssignment, context: BacklogRenderContext) -> some View {
        let chips = backlogChips(for: la, context: context)
        let title = viewModel.lessonTitle(for: la)
        return backlogLine(la, chips: chips, groupLabel: nil, groupCount: 1, context: context) {
            BacklogRowLayout(isCompact: context.isCompact, titleWidth: titleColumnWidth) {
                BacklogLessonTitle(title: title, areaColor: areaColor(for: la))
            } content: {
                lineContent(la, chips: chips, context: context)
            }
        }
    }

    /// A lesson with several groups: the title once, then each group on its
    /// own line.
    private func multiGroupRow(
        _ group: BacklogLessonGroup<CDLessonAssignment>,
        context: BacklogRenderContext
    ) -> some View {
        let first = group.items.first
        let title = first.map(viewModel.lessonTitle(for:)) ?? ""
        return BacklogRowLayout(isCompact: context.isCompact, titleWidth: titleColumnWidth) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
                BacklogLessonTitle(title: title, areaColor: first.map(areaColor(for:)) ?? .accentColor)
                Button("Merge Groups…") { coordinator.showMergeGroups(forLesson: group.lessonID) }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Move children between the \(group.items.count) groups of this lesson")
            }
            .padding(.horizontal, AppTheme.Spacing.small)
            .padding(.vertical, AppTheme.Spacing.verySmall)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(group.items.enumerated()), id: \.element.objectID) { index, la in
                    let chips = backlogChips(for: la, context: context)
                    let label = "Group \(index + 1)"
                    backlogLine(la, chips: chips, groupLabel: label, groupCount: group.items.count, context: context) {
                        HStack(alignment: .top, spacing: AppTheme.Spacing.small) {
                            Text(label)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .fixedSize()
                                // Level with the text inside the first chip.
                                .padding(.top, 3)
                            lineContent(la, chips: chips, context: context)
                        }
                    }
                }
            }
        }
    }

    /// The children, then what the line has to say on its right: partial
    /// readiness and its action for a brewing lesson, and the flags.
    private func lineContent(
        _ la: CDLessonAssignment,
        chips: [BacklogChip],
        context: BacklogRenderContext
    ) -> some View {
        let palette = context.palette
        return HStack(alignment: .top, spacing: AppTheme.Spacing.small) {
            if chips.isEmpty {
                Text("No children")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                FlowLayout(spacing: AppTheme.Spacing.xxsmall) {
                    ForEach(chips) { chip in
                        BacklogStudentChip(chip: chip, longWaitColor: palette.overdue)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            lineTrailing(la, context: context)
        }
    }

    @ViewBuilder
    private func lineTrailing(_ la: CDLessonAssignment, context: BacklogRenderContext) -> some View {
        let readiness = partialReadiness(of: la, context: context)
        let flags = flagBadges(for: la, context: context)
        if readiness != nil || !flags.isEmpty {
            HStack(spacing: AppTheme.Spacing.xsmall) {
                if let readiness {
                    Text("\(readiness.ready) of \(readiness.total) ready")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppColors.color(for: .brewing))
                    Button("Move Ready") { splitReadyToInbox(la, result: readiness.result) }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help("Make a ready presentation for the children who are ready now")
                }
                ForEach(flags) { flag in
                    BacklogFlagBadge(flag: flag)
                }
            }
            .fixedSize()
        }
    }

    // MARK: - Values

    /// The visible children on `la`, each resolved once: name, and the wait
    /// badge when they are at or past the long-wait threshold.
    private func backlogChips(for la: CDLessonAssignment, context: BacklogRenderContext) -> [BacklogChip] {
        let students = viewModel.studentsByID
        let waits = viewModel.daysSinceLastLessonByStudent
        let blocking = context.state == .waitingForWork ? getBlockingWork(la) : [:]
        let threshold = context.palette.overdueDays
        return la.resolvedStudentIDs.compactMap { sid in
            // Only the view model's visible roster: test and departed
            // children are not drawn, as the cards never drew them.
            guard let student = students[sid] else { return nil }
            var badge: String?
            var spoken: String?
            if let days = waits[sid], ReadyBacklog.isLongWait(days, threshold: threshold) {
                badge = ReadyBacklog.waitBadge(forDays: days)
                spoken = StudentWaitVocabulary.lessons.spokenDetail(
                    forDays: days == ReadyBacklog.neverTaught ? nil : days
                )
            }
            return BacklogChip(
                id: sid, name: student.shortName, waitBadge: badge, spokenWait: spoken,
                isBlocking: blocking[sid] != nil
            )
        }
    }

    /// Shown only when some but not all are ready: "0 of 3" says nothing a
    /// brewing lesson does not already say, and "3 of 3" is not brewing.
    func partialReadiness(
        of la: CDLessonAssignment,
        context: BacklogRenderContext
    ) -> BacklogReadiness? {
        guard context.state == .waitingForWork,
              let result = la.id.flatMap({ blockingResults[$0] }) else { return nil }
        let ready = result.readyStudentIDs.count
        let total = la.resolvedStudentIDs.count
        guard ready > 0, ready < total else { return nil }
        return BacklogReadiness(ready: ready, total: total, result: result)
    }

    /// The flags this line carries, minus the one the list is already
    /// filtered by — under Overdue, every row saying "Overdue" is noise.
    private func flagBadges(for la: CDLessonAssignment, context: BacklogRenderContext) -> [PresentationsFilterChip] {
        guard let id = la.id else { return [] }
        var flags: [PresentationsFilterChip] = []
        if context.state != .overdue, context.overdueIDs.contains(id) { flags.append(.overdue) }
        if context.state != .recentlyMissed, context.missedIDs.contains(id) { flags.append(.recentlyMissed) }
        return flags
    }

    func areaColor(for la: CDLessonAssignment) -> Color {
        if let area = viewModel.lessonsByID[la.resolvedLessonID]?.area, !area.isEmpty {
            return AppColors.color(forArea: area)
        }
        return .accentColor
    }
}
