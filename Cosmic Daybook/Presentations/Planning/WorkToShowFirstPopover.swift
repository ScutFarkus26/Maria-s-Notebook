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
    let onCheckToday: (CDWorkModel) -> Void

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
        let checkingToday = item.work.dueAt.map { AppCalendar.shared.isDateInToday($0) } ?? false
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
            Text(item.lessonName)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text([item.workTitle, item.work.status.displayName].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: AppTheme.Spacing.small) {
                if let workID = item.work.id {
                    Button("Open Work") { onOpenWork(workID) }
                        .buttonStyle(.bordered)
                }
                Button(checkingToday ? "On Today's Checks" : "Check Today") { onCheckToday(item.work) }
                    .buttonStyle(.borderedProminent)
                    .disabled(checkingToday)
            }
            .controlSize(.small)
        }
    }
}
