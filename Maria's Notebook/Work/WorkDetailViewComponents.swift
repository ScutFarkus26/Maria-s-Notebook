import SwiftUI

// MARK: - Practice Stats

struct PracticeStats {
    var totalSessions: Int = 0
    var totalDuration: String? = nil
    var avgQuality: Double? = nil
    var avgIndependence: Double? = nil
    var topBehaviors: [String] = []
    var needsReteaching: Int = 0
    var upcomingCheckIns: Int = 0
}

struct PracticeStatsCalculator {
    static func calculate(from sessions: [PracticeSession]) -> PracticeStats {
        var stats = PracticeStats()
        
        stats.totalSessions = sessions.count
        stats.totalDuration = formatDuration(from: sessions)
        stats.avgQuality = calculateAverage(values: sessions.compactMap { $0.practiceQuality })
        stats.avgIndependence = calculateAverage(values: sessions.compactMap { $0.independenceLevel })
        stats.topBehaviors = extractTopBehaviors(from: sessions, limit: 3)
        stats.needsReteaching = sessions.filter { $0.needsReteaching }.count
        stats.upcomingCheckIns = sessions.filter { $0.checkInScheduledFor != nil }.count
        
        return stats
    }
    
    private static func formatDuration(from sessions: [PracticeSession]) -> String? {
        let totalSeconds = sessions.compactMap { $0.duration }.reduce(0, +)
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
    
    private static func extractTopBehaviors(from sessions: [PracticeSession], limit: Int) -> [String] {
        var behaviorCounts: [String: Int] = [:]
        for session in sessions {
            for behavior in session.activeBehaviors {
                behaviorCounts[behavior, default: 0] += 1
            }
        }
        
        return behaviorCounts
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key }
    }
}

// MARK: - Work Check-In Row (Phase 6: renamed from WorkPlanItemRow)

struct WorkPlanItemRow: View {
    let item: WorkCheckIn
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            DateBadge(date: item.date)
            
            VStack(alignment: .leading, spacing: 4) {
                PurposeLabel(purpose: item.purpose)
                
                if !item.note.isEmpty {
                    Text(item.note)
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            DeleteButton(color: .red, action: onDelete)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.03))
        )
    }
}

// MARK: - Date Badge

private struct DateBadge: View {
    let date: Date
    
    var body: some View {
        VStack(spacing: 2) {
            Text(date.formatted(.dateTime.month(.abbreviated)))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(date.formatted(.dateTime.day()))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .frame(width: 48)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.blue.opacity(0.1))
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
                .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                action()
            }
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)
                .padding(8)
                .background(
                    Circle()
                        .fill(color.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Category Badge

private struct CategoryBadge: View {
    let category: NoteCategory

    var body: some View {
        Text(categoryLabel)
            .font(.system(size: AppTheme.FontSize.captionSmall, weight: .medium, design: .rounded))
            .foregroundStyle(categoryColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(categoryColor.opacity(0.15)))
    }

    private var categoryLabel: String {
        switch category {
        case .academic: return "Academic"
        case .behavioral: return "Behavioral"
        case .social: return "Social"
        case .emotional: return "Emotional"
        case .health: return "Health"
        case .attendance: return "Attendance"
        case .general: return "General"
        }
    }

    private var categoryColor: Color {
        switch category {
        case .academic: return .blue
        case .behavioral: return .orange
        case .social: return .green
        case .emotional: return .purple
        case .health: return .red
        case .attendance: return .indigo
        case .general: return .gray
        }
    }
}

// MARK: - Note Row View

struct NoteRowView: View {
    let note: Note
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(note.body)
                .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                CategoryBadge(category: note.category)
                
                Text(note.createdAt, style: .date)
                    .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
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
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
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
                    .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.primary.opacity(0.05))
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
                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
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
                    .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
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
                        .font(.system(size: AppTheme.FontSize.body, weight: .bold, design: .rounded))
                } icon: {
                    Image(systemName: icon)
                        .foregroundStyle(accentColor)
                }

                Spacer()

                if let trailing = trailing {
                    trailing()
                }
            }

            content()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.primary.opacity(0.03))
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
                    .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
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
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            Text(label)
                .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.08))
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
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("/ 5")
                    .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Text(label)
                .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.08))
        )
    }
}

struct BehaviorPill: View {
    let behavior: String

    var body: some View {
        Text(behavior)
            .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
            .foregroundStyle(.blue)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.blue.opacity(0.12))
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
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(label)
                    .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.08))
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
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.08))
        )
    }
}
