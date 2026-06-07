import SwiftUI
import CoreData

extension ProjectDetailView {
    var projectHeader: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
                    HStack(spacing: AppTheme.Spacing.small) {
                        Label(
                            club.isActive ? "Active Project" : "Completed Project",
                            systemImage: club.isActive ? "sparkle.magnifyingglass" : "checkmark.seal.fill"
                        )
                            .font(AppTheme.ScaledFont.captionSemibold)
                            .foregroundStyle(club.isActive ? AppColors.info : AppColors.success)
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
                            if let student = studentsByID[uuidString: sid] {
                                ProjectChip(text: StudentFormatter.displayName(for: student), icon: "person.fill")
                            } else {
                                ProjectChip(text: "Unknown", icon: "person.fill.questionmark")
                            }
                        }
                    }
                }
            }
        }
    }

    var dashboardMetrics: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: AppTheme.Spacing.small)],
            spacing: AppTheme.Spacing.small
        ) {
            ProjectMetricTile(
                title: "Students",
                value: "\(club.memberStudentIDsArray.count)",
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
            .background(
                Capsule().fill(Color.primary.opacity(UIConstants.OpacityConstants.subtle))
            )
    }
}
