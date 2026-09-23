import SwiftUI
import CoreData

extension ProjectDetailView {
    var projectHeader: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
                    HStack(spacing: AppTheme.Spacing.small) {
                        // "Active" used to mean only that nobody had pressed
                        // Mark Complete, so a project untouched since last year
                        // still called itself active. Say what has happened.
                        let standing = ProjectStandingBadge(status: ProjectActivity.status(of: club))
                        Label(standing.text, systemImage: standing.symbol)
                            .font(AppTheme.ScaledFont.captionSemibold)
                            .foregroundStyle(standing.color)
                    }

                    Text(club.title)
                        .font(.largeTitle.weight(.bold))

                    if let seed = club.bookTitle, !seed.isEmpty {
                        Label(seed, systemImage: SFSymbol.Education.bookClosed)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                HStack(spacing: AppTheme.Spacing.small) {
                    Button {
                        toggleProjectActive()
                    } label: {
                        Label(
                            club.isActive ? "Mark Complete" : "Reopen",
                            systemImage: club.isActive ? "checkmark.circle" : "arrow.counterclockwise"
                        )
                    }
                    .buttonStyle(.bordered)

                    Button {
                        showEditClub = true
                    } label: {
                        Label("Edit", systemImage: SFSymbol.Education.pencil)
                    }
                    .buttonStyle(.bordered)
                }
            }

            if !club.memberStudentIDsArray.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.small) {
                        ForEach(club.memberStudentIDsArray, id: \.self) { sid in
                            memberChip(for: sid)
                        }
                    }
                }
            }
        }
    }

    /// A member's chip.
    ///
    /// The member list keeps every child ever added, so a girl who has since
    /// withdrawn or transferred is still on it. She used to read as "Unknown"
    /// here — `studentsByID` holds only the enrolled — which hid the fact that
    /// the project is carrying a child who has left. Name her, and say so.
    @ViewBuilder
    private func memberChip(for sid: String) -> some View {
        if let student = studentsByID[uuidString: sid] {
            ProjectChip(text: student.shortName, icon: "person.fill")
        } else if let former = formerStudentsByID[uuidString: sid] {
            ProjectChip(
                text: "\(former.shortName) (former)",
                icon: "person.fill.badge.minus"
            )
        } else {
            ProjectChip(text: "Unknown", icon: "person.fill.questionmark")
        }
    }

    var dashboardMetrics: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: AppTheme.Spacing.small)],
            spacing: AppTheme.Spacing.small
        ) {
            ProjectMetricTile(
                title: "Students",
                value: "\(enrolledMemberCount)",
                systemImage: SFSymbol.People.person2,
                color: AppColors.info
            )
            ProjectMetricTile(
                title: "Lessons",
                value: "\(linkedLessons.count)",
                systemImage: SFSymbol.Education.bookClosed,
                color: AppColors.success
            )
            ProjectMetricTile(
                title: "Follow-Ups",
                value: "\(openFollowUps.count)",
                systemImage: "arrow.uturn.forward.circle",
                color: AppColors.warning
            )
            ProjectMetricTile(
                title: "Questions",
                value: "\(openQuestions.count)",
                systemImage: "questionmark.bubble",
                color: AppColors.attention
            )
        }
    }
}

/// How a project's standing reads in a header: running, gone quiet, or finished.
///
/// Replaces the old "Active / Completed" pair, which could only report the
/// `isActive` flag — set true at creation and never revisited, so a project
/// nobody had touched since last year still announced itself as active.
struct ProjectStandingBadge {
    let text: String
    let symbol: String
    let color: Color

    init(status: ProjectActivity.Status) {
        switch status {
        case .active:
            text = "Active Project"
            symbol = "sparkle.magnifyingglass"
            color = AppColors.info
        case .closed:
            text = "Completed Project"
            symbol = "checkmark.seal.fill"
            color = AppColors.success
        case .dormant(let since):
            let when = since.map { " since \(DateFormatters.mediumDate.string(from: $0))" } ?? ""
            text = "Dormant\(when)"
            symbol = "moon.zzz.fill"
            color = AppColors.warning
        }
    }
}

private struct ProjectMetricTile: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(Circle().fill(color.opacity(UIConstants.OpacityConstants.medium)))

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                Text(value)
                    .font(.title2.weight(.bold))
                Text(title)
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(AppTheme.Spacing.small)
        .background(Color.primary.opacity(UIConstants.OpacityConstants.trace))
        .cornerRadius(UIConstants.CornerRadius.small)
    }
}

private struct ProjectChip: View {
    let text: String
    let icon: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.subheadline)
            .padding(.vertical, AppTheme.Spacing.verySmall)
            .padding(.horizontal, AppTheme.Spacing.small + 2)
            .capsuleFill(Color.primary.opacity(UIConstants.OpacityConstants.subtle))
    }
}
