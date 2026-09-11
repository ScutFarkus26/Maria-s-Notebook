// ProjectSidebarRow.swift
// One project in the Projects sidebar. Split out of ProjectsRootView.swift for
// the 400-line limit.

import SwiftUI
import CoreData

/// A row component for displaying a project in a list view.
/// Shows the project's icon (colored circle with project icon), title, and member count.
/// Design matches AreaListRow/StudentListRow for visual consistency across the app.
struct ProjectSidebarRow: View {
    let club: CDProject
    let isSelected: Bool
    let lastSessionDate: Date?
    /// Running, quiet since the school year began, or finished — judged from
    /// what has happened to the project, not from the `isActive` flag alone.
    let status: ProjectActivity.Status
    /// Members still in the class. The stored member list keeps every child
    /// ever added, so counting it named departed girls as current members.
    let memberCount: Int

    private var projectColor: Color {
        // Use a consistent color for projects, or could be customized per project
        AppColors.color(forArea: "Reading")
    }

    private var statusDotColor: Color {
        switch status {
        case .active: return projectColor
        case .dormant: return AppColors.warning
        case .closed: return AppColors.success
        }
    }

    private var statusCaption: (text: String, color: Color)? {
        switch status {
        case .active:
            return nil
        case .closed:
            return ("Completed", AppColors.success)
        case .dormant(let since):
            let when = since.map { DateFormatters.mediumDate.string(from: $0) }
            return (when.map { "Dormant since \($0)" } ?? "Dormant", AppColors.warning)
        }
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.compact) {
            // Icon circle with project icon (matching AreaListRow/StudentListRow avatar style)
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                projectColor.opacity(UIConstants.OpacityConstants.faint + 0.72),
                                projectColor
                            ]),
                            center: .center,
                            startRadius: 8,
                            endRadius: 24
                        )
                    )
                    .frame(width: 40, height: 40)

                Image(systemName: SFSymbol.People.person3Fill)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }

            // Title and member count
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                Text(club.title)
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                // Member count as secondary text
                HStack(spacing: AppTheme.Spacing.xsmall) {
                    Circle().fill(statusDotColor).frame(width: 6, height: 6)
                    Text("\(memberCount) \(memberCount == 1 ? "student" : "students")")
                        .font(AppTheme.ScaledFont.captionSmallSemibold)
                        .foregroundStyle(.secondary)
                    if let statusCaption {
                        Text(statusCaption.text)
                            .font(AppTheme.ScaledFont.captionSmallSemibold)
                            .foregroundStyle(statusCaption.color)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, AppTheme.Spacing.verySmall)
        .padding(.horizontal, AppTheme.Spacing.small)
        .contentShape(Rectangle())
    }
}
