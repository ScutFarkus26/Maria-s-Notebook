// WorkToShowFirstPopover.swift
// What a marked child chip on the Scheduled strip opens: the work she still
// has open from earlier in the lesson's sequence, each with a way to open it
// or put it on today's checks.
//
// A popover because it is opened by a click or a tap on the chip, never by
// hovering (the Mac's hover gets a `.help` tooltip instead, Apple guidance 5).

import CoreData
import SwiftUI

struct WorkToShowFirstPopover: View {
    let childName: String
    let items: [WorkToShowFirst.Item]
    let onOpenWork: (UUID) -> Void
    let onCheckToday: (WorkToShowFirst.Item) -> Void

    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(childName) has work to check first")
                    .font(.headline)
                Text("Still open from earlier in this sequence.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                Divider()
                row(item)
            }
        }
        .padding(AppTheme.Spacing.medium)
        .frame(minWidth: 260, idealWidth: 300, maxWidth: 360, alignment: .leading)
        .presentationCompactAdaptation(.popover)
    }

    private func row(_ item: WorkToShowFirst.Item) -> some View {
        // From the work's check-ins, not its due date: a row can be due today
        // with no check planned, or have one today and a later due date.
        let plan = WorkToShowFirst.todayCheck(for: item.work, in: viewContext)
        let onToday = if case .onToday = plan { true } else { false }
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
            Text(item.lessonName)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text([item.workTitle, item.work.status.displayName].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // "Move Thursday's Check to Today" can outgrow the popover beside
            // Open Work; the two then stack.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppTheme.Spacing.small) { buttons(item, plan: plan, onToday: onToday) }
                VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                    buttons(item, plan: plan, onToday: onToday)
                }
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func buttons(_ item: WorkToShowFirst.Item, plan: WorkToShowFirst.TodayCheck, onToday: Bool) -> some View {
        if let workID = item.work.id {
            Button("Open Work") { onOpenWork(workID) }
                .buttonStyle(.bordered)
        }
        Button(WorkToShowFirst.checkTodayTitle(plan)) { onCheckToday(item) }
            .buttonStyle(.borderedProminent)
            .disabled(onToday)
    }
}
