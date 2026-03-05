import SwiftUI
import SwiftData

// MARK: - Display Mode Variants

extension PracticeSessionCard {

    // MARK: - Compact View

    var compactView: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 8) {
                // Session type icon
                Image(systemName: session.isGroupSession ? "person.2.fill" : "person.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(session.isGroupSession ? .blue : .secondary)

                // Date
                Text(formatDate(session.date))
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.primary)

                // Student names
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
                    .fill(Color.primary.opacity(0.03))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Standard View

    var standardView: some View {
        Button(action: { onTap?() }) {
            VStack(alignment: .leading, spacing: 12) {
                sessionHeader

                // Students
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

                // Quality metrics (if available)
                if session.practiceQuality != nil || session.independenceLevel != nil {
                    HStack(spacing: 12) {
                        if let quality = session.practiceQuality {
                            qualityIndicator(level: quality, color: .blue, label: "Quality")
                        }

                        if let independence = session.independenceLevel {
                            qualityIndicator(level: independence, color: .green, label: "Independence")
                        }
                    }
                }

                // Behavior tags (if any)
                if !session.activeBehaviors.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(session.activeBehaviors, id: \.self) { behavior in
                                behaviorTag(behavior)
                            }
                        }
                    }
                }

                // Notes preview
                if !session.sharedNotes.isEmpty {
                    Text(session.sharedNotes)
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .italic()
                }

                // Footer metadata
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
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(session.isGroupSession ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expanded View

    var expandedView: some View {
        VStack(alignment: .leading, spacing: 16) {
            expandedHeader
            Divider()

            // Students section
            VStack(alignment: .leading, spacing: 8) {
                Text("Participants")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                ForEach(students) { student in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 8, height: 8)

                        Text(StudentFormatter.displayName(for: student))
                            .font(AppTheme.ScaledFont.bodySemibold)
                    }
                }
            }

            // Quality metrics
            if session.practiceQuality != nil || session.independenceLevel != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quality Metrics")
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    HStack(spacing: 16) {
                        if let quality = session.practiceQuality, let label = session.practiceQualityLabel {
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

                        if let independence = session.independenceLevel, let label = session.independenceLevelLabel {
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

            // Observable behaviors
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

            // Next steps / action items
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

            // Work items section
            if !workItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Work Items")
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    ForEach(workItems, id: \.id) { work in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.green.opacity(0.2))
                                .frame(width: 8, height: 8)

                            Text(work.title)
                                .font(AppTheme.ScaledFont.body)
                        }
                    }
                }
            }

            // Session notes
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

            // Metadata footer
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
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(session.isGroupSession ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1.5)
        )
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

                Text(formatDateLong(session.date))
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

            Text(formatDate(session.date))
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
        }
    }
}
