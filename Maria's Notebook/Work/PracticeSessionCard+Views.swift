import SwiftUI
import CoreData

// MARK: - Display Mode Variants

extension PracticeSessionCard {

    // MARK: - Compact View

    var compactView: some View {
        Button(action: { onTap?() }, label: {
            HStack(spacing: 8) {
                // Session type icon
                Image(systemName: session.isGroupSession ? "person.2.fill" : "person.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(session.isGroupSession ? .blue : .secondary)

                // Date
                Text(formatDate(session.date ?? Date()))
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.primary)

                // CDStudent names
                Text(studentNames)
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                // Duration if available
                if let duration = session.durationFormatted {
                    Text(duration)
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(UIConstants.OpacityConstants.whisper))
            )
        })
        .buttonStyle(.plain)
    }

    // MARK: - Standard View

    var standardView: some View {
        Button(action: { onTap?() }, label: {
            VStack(alignment: .leading, spacing: 12) {
                sessionHeader
                standardStudentsRow
                standardQualityMetrics
                standardBehaviorTags
                standardNotesPreview
                standardFooter
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(UIConstants.OpacityConstants.hint))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(session.isGroupSession ? Color.blue.opacity(UIConstants.OpacityConstants.semi) : Color.clear, lineWidth: 1)
            )
        })
        .buttonStyle(.plain)
    }

    private var standardStudentsRow: some View {
        HStack(spacing: 6) {
            ForEach(students) { student in
                Text(StudentFormatter.displayName(for: student))
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(.primary)

                if student.id != students.last?.id {
                    Text("&")
                        .font(AppTheme.ScaledFont.body)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var standardQualityMetrics: some View {
        if session.practiceQualityValue != nil || session.independenceLevelValue != nil {
            HStack(spacing: 12) {
                if let quality = session.practiceQualityValue {
                    qualityIndicator(level: quality, color: .blue, label: "Quality")
                }

                if let independence = session.independenceLevelValue {
                    qualityIndicator(level: independence, color: .green, label: "Independence")
                }
            }
        }
    }

    @ViewBuilder
    private var standardBehaviorTags: some View {
        if !session.activeBehaviors.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(session.activeBehaviors, id: \.self) { behavior in
                        behaviorTag(behavior)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var standardNotesPreview: some View {
        if !session.sharedNotes.isEmpty {
            Text(session.sharedNotes)
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .italic()
        }
    }

    private var standardFooter: some View {
        HStack(spacing: 12) {
            if let duration = session.durationFormatted {
                Label(duration, systemImage: "clock.fill")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
            }

            if let location = session.location, !location.isEmpty {
                Label(location, systemImage: "location.fill")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Work items count
            if session.workItemCount > 1 {
                Text("\(session.workItemCount) items")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Expanded View

    var expandedView: some View {
        VStack(alignment: .leading, spacing: 16) {
            expandedHeader
            Divider()
            expandedParticipants
            expandedQualityMetrics
            expandedBehaviors
            expandedNextSteps
            expandedWorkItems
            expandedNotes
            expandedMetadataFooter
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.hint))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(session.isGroupSession ? Color.blue.opacity(UIConstants.OpacityConstants.semi) : Color.clear, lineWidth: 1.5)
        )
    }

    @ViewBuilder
    private var expandedParticipants: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Participants")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(students) { student in
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.blue.opacity(UIConstants.OpacityConstants.moderate))
                        .frame(width: 8, height: 8)

                    Text(StudentFormatter.displayName(for: student))
                        .font(AppTheme.ScaledFont.bodySemibold)
                }
            }
        }
    }

    @ViewBuilder
    private var expandedQualityMetrics: some View {
        if session.practiceQualityValue != nil || session.independenceLevelValue != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("Quality Metrics")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                HStack(spacing: 16) {
                    if let quality = session.practiceQualityValue, let label = session.practiceQualityLabel {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Engagement")
                                .font(AppTheme.ScaledFont.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                ForEach(1...5, id: \.self) { level in
                                    Circle()
                                        .fill(Color.blue.opacity(quality >= level ? 1.0 : 0.2))
                                        .frame(width: 12, height: 12)
                                }
                                Text(label)
                                    .font(AppTheme.ScaledFont.captionSemibold)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }

                    if let independence = session.independenceLevelValue, let label = session.independenceLevelLabel {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Independence")
                                .font(AppTheme.ScaledFont.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                ForEach(1...5, id: \.self) { level in
                                    Circle()
                                        .fill(Color.green.opacity(independence >= level ? 1.0 : 0.2))
                                        .frame(width: 12, height: 12)
                                }
                                Text(label)
                                    .font(AppTheme.ScaledFont.captionSemibold)
                                    .foregroundStyle(AppColors.success)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var expandedBehaviors: some View {
        if !session.activeBehaviors.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Observed Behaviors")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                FlowLayout(spacing: 6) {
                    ForEach(session.activeBehaviors, id: \.self) { behavior in
                        behaviorTag(behavior)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var expandedNextSteps: some View {
        if session.hasActionFlags || session.hasNextSteps {
            VStack(alignment: .leading, spacing: 8) {
                Text("Next Steps")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                VStack(alignment: .leading, spacing: 6) {
                    if session.needsReteaching {
                        actionRow(icon: "arrow.counterclockwise", text: "Needs Reteaching", color: .orange)
                    }
                    if session.readyForCheckIn {
                        actionRow(icon: "checkmark.circle", text: "Ready for Check-in", color: .blue)
                    }
                    if session.readyForAssessment {
                        actionRow(icon: "star.circle", text: "Ready for Assessment", color: .green)
                    }
                    if let checkIn = session.checkInScheduledFor {
                        actionRow(icon: "calendar", text: "Check-in: \(formatDate(checkIn))", color: .indigo)
                    }
                    if !session.followUpActions.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.purple)
                            Text(session.followUpActions)
                                .font(AppTheme.ScaledFont.caption)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var expandedWorkItems: some View {
        if !workItems.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Work Items")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                ForEach(workItems, id: \.id) { work in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.green.opacity(UIConstants.OpacityConstants.moderate))
                            .frame(width: 8, height: 8)

                        Text(work.title)
                            .font(AppTheme.ScaledFont.body)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var expandedNotes: some View {
        if !session.sharedNotes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Notes")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(session.sharedNotes)
                    .font(AppTheme.ScaledFont.body)
                    .foregroundStyle(.primary)
            }
        }
    }

    private var expandedMetadataFooter: some View {
        HStack(spacing: 16) {
            if let duration = session.durationFormatted {
                Label(duration, systemImage: "clock.fill")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
            }

            if let location = session.location, !location.isEmpty {
                Label(location, systemImage: "location.fill")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Header Components

    var expandedHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: session.isGroupSession ? "person.2.fill" : "person.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(session.isGroupSession ? .blue : .secondary)

                    Text(session.isGroupSession ? "Group Practice Session" : "Solo Practice Session")
                        .font(AppTheme.ScaledFont.calloutSemibold)
                }

                Text(formatDateLong(session.date ?? Date()))
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    var sessionHeader: some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: session.isGroupSession ? "person.2.fill" : "person.fill")
                    .font(.system(size: 10))
                Text(session.isGroupSession ? "Group" : "Solo")
                    .font(AppTheme.ScaledFont.captionSemibold)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(session.isGroupSession ? Color.blue : Color.gray)
            )

            Spacer()

            Text(formatDate(session.date ?? Date()))
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
        }
    }
}
