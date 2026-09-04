import CoreData
import SwiftUI

struct FollowingPresentationsView: View {
    enum Style {
        case full
        case today
        case student
    }

    let style: Style
    var studentID: UUID?
    var searchText: String = ""
    var searchTokens: [String] = []
    var onOpen: (CDLessonAssignment) -> Void
    var onViewAll: (() -> Void)?

    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDLessonPresentation.presentedAt, ascending: true)],
        predicate: NSPredicate(format: "followUpActionRaw != nil AND followUpResolvedAt == nil"),
        animation: .default
    ) private var rows: FetchedResults<CDLessonPresentation>
    @FetchRequest(sortDescriptors: []) private var assignments: FetchedResults<CDLessonAssignment>
    @FetchRequest(sortDescriptors: []) private var lessons: FetchedResults<CDLesson>
    @FetchRequest(sortDescriptors: []) private var students: FetchedResults<CDStudent>

    private var groups: [FollowingPresentationGroup] {
        FollowingPresentationsService.groups(
            rows: Array(rows),
            assignments: Array(assignments),
            lessons: Array(lessons),
            students: Array(students),
            studentID: studentID,
            searchText: searchText,
            searchTokens: searchTokens,
            context: viewContext
        )
    }

    var body: some View {
        switch style {
        case .full:
            fullContent
        case .today:
            todayContent
        case .student:
            studentContent
        }
    }
}

private extension FollowingPresentationsView {
    @ViewBuilder
    var fullContent: some View {
        if groups.isEmpty {
            ContentUnavailableView(
                "No Presentations to Follow",
                systemImage: "eye.circle",
                description: Text("New presentations stay here until you observe the work or plan what comes next.")
            )
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 290, maximum: 420), spacing: 14)],
                    alignment: .leading,
                    spacing: 14
                ) {
                    ForEach(groups) { group in
                        FollowingPresentationCard(group: group, density: .full, onOpen: onOpen)
                    }
                }
                .padding(18)
            }
        }
    }

    @ViewBuilder
    var todayContent: some View {
        if !groups.isEmpty {
            Section {
                VStack(spacing: 0) {
                    ForEach(Array(groups.prefix(3)).enumerated(), id: \.element.id) { index, group in
                        FollowingPresentationCard(group: group, density: .compact, onOpen: onOpen)
                        if index < min(groups.count, 3) - 1 {
                            Divider().padding(.leading, 34)
                        }
                    }

                    if groups.count > 3, let onViewAll {
                        Divider()
                        Button("View All \(groups.count)", action: onViewAll)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 10)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                sectionHeader("Following Presentations")
            }
        }
    }

    @ViewBuilder
    var studentContent: some View {
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("Following Presentations", systemImage: "eye.circle")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppTheme.Spacing.xsmall)

                ForEach(groups) { group in
                    FollowingPresentationCard(group: group, density: .student, onOpen: onOpen)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.xsmall)
        }
    }

    func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(AppTheme.ScaledFont.caption)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.8)
    }
}

private struct FollowingPresentationCard: View {
    enum Density {
        case full
        case compact
        case student
    }

    let group: FollowingPresentationGroup
    let density: Density
    let onOpen: (CDLessonAssignment) -> Void

    var body: some View {
        Button(action: openAssignment) { cardContent }
        .buttonStyle(.plain)
        .disabled(group.assignment == nil)
        .accessibilityLabel(accessibilityLabel)
    }

    private func openAssignment() {
        if let assignment = group.assignment {
            onOpen(assignment)
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: density == .compact ? 5 : 9) {
            titleRow

            Text(group.childNames)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(density == .compact ? 1 : 2)

            timingRow
            childDetails
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(density == .compact ? 8 : 14)
        .background(cardBackground)
        .contentShape(Rectangle())
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "eye.circle.fill")
                .foregroundStyle(.blue)
            Text(group.lessonName)
                .font(density == .compact ? .subheadline.weight(.semibold) : .headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer()
            if group.assignment != nil {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var timingRow: some View {
        HStack(spacing: 6) {
            Text(group.actionSummary)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
            Text("•")
                .foregroundStyle(.tertiary)
            Text(timingText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var childDetails: some View {
        if density == .full, group.children.count > 1 {
            Divider()
            ForEach(group.children) { child in
                HStack {
                    Text(child.studentName)
                    Spacer()
                    Text(child.row.followUpAction?.shortTitle ?? "Keep Watching")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }

    private var timingText: String {
        if let reviewAt = group.earliestReviewAt {
            return "Review \(reviewAt.formatted(date: .abbreviated, time: .omitted))"
        }
        let days = group.schoolDaysSincePresentation
        return days == 0 ? "Presented today" : "\(days) school day\(days == 1 ? "" : "s") since presentation"
    }

    @ViewBuilder
    private var cardBackground: some View {
        if density == .compact {
            Color.clear
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                )
        }
    }

    private var accessibilityLabel: String {
        "Follow \(group.lessonName) for \(group.childNames). \(group.actionSummary). \(timingText)."
    }
}
