import CoreData
import SwiftUI

/// "Before you start": above "Who was there?" in the present-a-lesson sheet,
/// the work the children on the plan still have open from earlier in this
/// lesson's sequence (`WorkToShowFirst`), each with a way to close it there
/// and then. The sheet shows it only when there is something to list.
///
/// A shared row (project or book-club work) is one row for every child on it,
/// so logging it here would close her classmates' part too; it offers Open
/// Work instead, where the guide sees everyone on it.
struct PresentationBeforeYouStartSection: View {
    let students: [CDStudent]
    let showFirst: WorkToShowFirst.ByChild
    /// Logs one row through `WorkToShowFirst.log`.
    let onLog: (WorkToShowFirst.Item, WorkStatus) -> Void
    let onOpenWork: (UUID) -> Void

    /// The three ways to close earlier work from here: no verdict, the
    /// verdict, or not yet.
    static let statuses: [WorkStatus] = [.done, .mastered, .keepPracticing]

    /// The rows listed: each child on the plan, then her earlier work. A
    /// child in `showFirst` who isn't among `students` isn't listed.
    static func rows(
        students: [CDStudent], showFirst: WorkToShowFirst.ByChild
    ) -> [(student: CDStudent, item: WorkToShowFirst.Item)] {
        students.flatMap { student in
            (student.id.flatMap { showFirst[$0] } ?? []).map { (student, $0) }
        }
    }

    private var rows: [(student: CDStudent, item: WorkToShowFirst.Item)] {
        Self.rows(students: students, showFirst: showFirst)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Before you start")
                    .font(AppTheme.ScaledFont.titleSmall)
                Text("Work still open from earlier in this sequence. Check it first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.item.id) { index, row in
                    if index > 0 { Divider() }
                    rowView(row.student, row.item)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large, style: .continuous)
                    .strokeBorder(
                        AppColors.color(for: .brewing).opacity(UIConstants.OpacityConstants.semi), lineWidth: 1
                    )
            )
        }
    }

    private func rowView(_ student: CDStudent, _ item: WorkToShowFirst.Item) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                label(student, item)
                Spacer(minLength: 8)
                buttons(item)
            }
            VStack(alignment: .leading, spacing: 8) {
                label(student, item)
                buttons(item)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func label(_ student: CDStudent, _ item: WorkToShowFirst.Item) -> some View {
        HStack(spacing: 10) {
            Image(systemName: WorkToShowFirst.glyph)
                .foregroundStyle(AppColors.color(for: .brewing))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(student.shortName) · \(item.lessonName)")
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .fixedSize(horizontal: false, vertical: true)
                Text(
                    [item.workTitle, item.work.status.displayName, item.isHersAlone ? nil : "Shared work"]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let workID = item.work.id { onOpenWork(workID) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the work")
    }

    @ViewBuilder
    private func buttons(_ item: WorkToShowFirst.Item) -> some View {
        if item.isHersAlone {
            HStack(spacing: 6) {
                ForEach(Self.statuses) { status in
                    Button(status.displayName) { onLog(item, status) }
                        .buttonStyle(.bordered)
                        .tint(status.color)
                }
            }
            .controlSize(.small)
            .fixedSize()
        } else if let workID = item.work.id {
            Button("Open Work") { onOpenWork(workID) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
                .accessibilityHint("Shared with other children, so it's logged from the work itself")
        }
    }
}
