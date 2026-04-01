// swiftlint:disable file_length
import SwiftUI

// MARK: - Practice Stats

struct PracticeStats {
    var totalSessions: Int = 0
    var totalDuration: String?
    var avgQuality: Double?
    var avgIndependence: Double?
    var topBehaviors: [String] = []
    var needsReteaching: Int = 0
    var upcomingCheckIns: Int = 0
}

struct PracticeStatsCalculator {
    static func calculate(from sessions: [CDPracticeSession]) -> PracticeStats {
        var stats = PracticeStats()
        
        stats.totalSessions = sessions.count
        stats.totalDuration = formatDuration(from: sessions)
        stats.avgQuality = calculateAverage(values: sessions.compactMap(\.practiceQualityValue))
        stats.avgIndependence = calculateAverage(values: sessions.compactMap(\.independenceLevelValue))
        stats.topBehaviors = extractTopBehaviors(from: sessions, limit: 3)
        stats.needsReteaching = sessions.filter(\.needsReteaching).count
        stats.upcomingCheckIns = sessions.filter { $0.checkInScheduledFor != nil }.count
        
        return stats
    }
    
    private static func formatDuration(from sessions: [CDPracticeSession]) -> String? {
        let totalSeconds = sessions.compactMap(\.durationInterval).reduce(0, +)
        guard totalSeconds > 0 else { return nil }
        
        let minutes = Int(totalSeconds / 60)
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = Double(minutes) / 60.0
            return String(format: "%.1f hrs", hours)
        }
    }
    
    private static func calculateAverage(values: [Int]) -> Double? {
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }
    
    private static func extractTopBehaviors(from sessions: [CDPracticeSession], limit: Int) -> [String] {
        var behaviorCounts: [String: Int] = [:]
        for session in sessions {
            for behavior in session.activeBehaviors {
                behaviorCounts[behavior, default: 0] += 1
            }
        }
        
        return behaviorCounts
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map(\.key)
    }
}

// MARK: - Work Check-In Row (Phase 6: renamed from WorkPlanItemRow)

struct WorkPlanItemRow: View {
    let item: CDWorkCheckIn
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            DateBadge(date: item.date ?? Date())
            
            VStack(alignment: .leading, spacing: 4) {
                PurposeLabel(purpose: item.purpose)
            }
            
            Spacer()
            
            DeleteButton(color: .red, action: onDelete)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.whisper))
        )
    }
}

// MARK: - Date Badge

private struct DateBadge: View {
    let date: Date
    
    var body: some View {
        VStack(spacing: 2) {
            Text(date.formatted(.dateTime.month(.abbreviated)))
                .font(AppTheme.ScaledFont.captionSmallSemibold)
                .foregroundStyle(.secondary)
            Text(date.formatted(.dateTime.day()))
                .font(AppTheme.ScaledFont.calloutBold)
                .foregroundStyle(.primary)
        }
        .frame(width: 48)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.blue.opacity(UIConstants.OpacityConstants.light))
        )
    }
}

// MARK: - Purpose Label (Phase 6: renamed from ReasonLabel)

private struct PurposeLabel: View {
    let purpose: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 12, weight: .medium))
            Text(purpose.isEmpty ? "Check-In" : purpose)
                .font(AppTheme.ScaledFont.bodySemibold)
        }
        .foregroundStyle(.primary)
    }
}

// MARK: - Delete Button

private struct DeleteButton: View {
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button {
            adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                action()
            }
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)
                .padding(8)
                .background(
                    Circle()
                        .fill(color.opacity(UIConstants.OpacityConstants.light))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - CDNote Tags Display

private struct NoteTagsRow: View {
    let tags: [String]

    var body: some View {
        if !tags.isEmpty {
            HStack(spacing: 4) {
                ForEach(tags.prefix(3), id: \.self) { tag in
                    TagBadge(tag: tag, compact: true)
                }
            }
        }
    }
}

// MARK: - CDNote Row View

struct NoteRowView: View {
    let note: CDNote
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(note.body)
                .font(AppTheme.ScaledFont.body)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                NoteTagsRow(tags: note.tagsArray)

                Text(note.createdAt ?? Date(), style: .date)
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(.tertiary)
                
                Spacer()
                
                HStack(spacing: 8) {
                    ActionIconButton(icon: "pencil.circle.fill", color: .blue, action: onEdit)
                    ActionIconButton(icon: "trash.circle.fill", color: .red, action: onDelete)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.whisper))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint), lineWidth: 1)
        )
    }
}

// MARK: - Action Icon Button

private struct ActionIconButton: View {
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Save Cancel Buttons

struct SaveCancelButtons: View {
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onCancel()
            } label: {
                Text("Cancel")
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.primary.opacity(UIConstants.OpacityConstants.hint))
                    )
            }
            .buttonStyle(.plain)

            Button {
                onSave()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Save")
                        .font(AppTheme.ScaledFont.bodySemibold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.accentColor)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Action Buttons

struct IconActionButton: View {
    let icon: String
    let color: Color
    let backgroundColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(Circle().fill(backgroundColor))
        }
        .buttonStyle(.plain)
    }
}

struct RoundedActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(AppTheme.ScaledFont.bodySemibold)
            }
            .foregroundStyle(color)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(color.opacity(UIConstants.OpacityConstants.medium))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Section Components

struct DetailSectionCard<Content: View, Trailing: View>: View {
    let title: String
    let icon: String
    let accentColor: Color
    var trailing: (() -> Trailing)?
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        icon: String,
        accentColor: Color,
        trailing: (() -> Trailing)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) where Trailing == EmptyView {
        self.title = title
        self.icon = icon
        self.accentColor = accentColor
        self.trailing = nil
        self.content = content
    }

    init(
        title: String,
        icon: String,
        accentColor: Color,
        @ViewBuilder trailing: @escaping () -> Trailing,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.accentColor = accentColor
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label {
                    Text(title)
                        .font(AppTheme.ScaledFont.bodyBold)
                } icon: {
                    Image(systemName: icon)
                        .foregroundStyle(accentColor)
                }

                Spacer()

                if let trailing {
                    trailing()
                }
            }

            content()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.whisper))
        )
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text(title)
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - Metric Components

struct MetricStatBox: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(color)

                Text(value)
                    .font(AppTheme.ScaledFont.header)
                    .foregroundStyle(.primary)
            }

            Text(label)
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(UIConstants.OpacityConstants.subtle))
        )
    }
}

struct QualityMetricBox: View {
    let level: Double
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(color)

                Text(String(format: "%.1f", level))
                    .font(AppTheme.ScaledFont.header)
                    .foregroundStyle(.primary)

                Text("/ 5")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
            }

            Text(label)
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(UIConstants.OpacityConstants.subtle))
        )
    }
}

struct BehaviorPill: View {
    let behavior: String

    var body: some View {
        Text(behavior)
            .font(AppTheme.ScaledFont.captionSemibold)
            .foregroundStyle(.blue)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.blue.opacity(UIConstants.OpacityConstants.medium))
            )
    }
}

struct ActionItemBox: View {
    let count: Int
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(count)")
                    .font(AppTheme.ScaledFont.calloutBold)
                    .foregroundStyle(.primary)

                Text(label)
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(UIConstants.OpacityConstants.subtle))
        )
    }
}

struct FlagRow: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)

            Text(text)
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(color)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(UIConstants.OpacityConstants.subtle))
        )
    }
}
