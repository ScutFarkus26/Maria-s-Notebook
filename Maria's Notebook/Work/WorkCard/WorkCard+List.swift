import SwiftUI

/// List mode content for WorkCard
/// Displays: work type icon, title, subtitle, trailing badge (open count or status)
/// Supports: tap to open
struct WorkCardListContent: View {
    let config: WorkCard.ListModeConfig

    private var workType: WorkCardWorkType {
        // Use kind for work type
        return WorkCardWorkType(from: config.work.kind ?? .research)
    }

    var body: some View {
        Button {
            config.onOpen(config.work)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: workType.icon)
                    .foregroundStyle(workType.color)

                VStack(alignment: .leading, spacing: 2) {
                    Text(config.title)
                        .font(AppTheme.ScaledFont.calloutSemibold)
                        .lineLimit(1)
                    Text(config.subtitle)
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let badge = config.badge {
                    badgeView(for: badge)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func badgeView(for badge: WorkCardBadge) -> some View {
        switch badge {
        case .openCount(let count):
            if count > 0 {
                Text("\(count)")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(workType.color.opacity(UIConstants.OpacityConstants.accent)))
                    .foregroundStyle(workType.color)
            }
        case .status(let status):
            Text(status)
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    let stack = CoreDataStack.preview
    let ctx = stack.viewContext

    let w1 = CDWorkModel(context: ctx)
    w1.status = .active; w1.studentID = UUID().uuidString; w1.lessonID = UUID().uuidString
    let w2 = CDWorkModel(context: ctx)
    w2.status = .complete; w2.studentID = UUID().uuidString; w2.lessonID = UUID().uuidString

    return List {
        WorkCard.list(
            work: w1,
            title: "Long Division Practice",
            subtitle: "Math • Jan 15, 2025",
            badge: .openCount(3),
            onOpen: { _ in }
        )

        WorkCard.list(
            work: w2,
            title: "Research CDProject",
            subtitle: "Science • Jan 10, 2025",
            badge: .status("complete"),
            onOpen: { _ in }
        )
    }
    .previewEnvironment(using: stack)
}
