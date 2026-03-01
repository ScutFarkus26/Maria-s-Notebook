// StudentProgressComponents.swift
// Reusable components extracted from StudentProgressTab

import SwiftUI
import SwiftData

// MARK: - Progress Card Header

/// Standard header for enrollment and report cards showing icon, title, and status badge
struct ProgressCardHeader: View {
    let iconName: String
    let color: Color
    let title: String
    let subtitle: String
    let isComplete: Bool
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Icon/indicator
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: iconName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTheme.ScaledFont.titleSmall)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Status badge
            StatusBadge(isComplete: isComplete, isActive: isActive)
        }
    }
}

// MARK: - Status Badge

/// Circular status badge showing complete/active/pending state
struct StatusBadge: View {
    let isComplete: Bool
    let isActive: Bool

    var body: some View {
        let showCheck = isComplete || isActive
        ZStack {
            Circle()
                .fill(
                    showCheck
                        ? LinearGradient(colors: [Color.green, Color.green.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [Color.secondary.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 36, height: 36)

            Image(systemName: showCheck ? "checkmark" : "circle")
                .font(.system(size: 18, weight: showCheck ? .bold : .medium))
                .foregroundStyle(showCheck ? .white : .secondary)
        }
    }
}

// MARK: - Progress Stats Section

/// Large progress stats showing completed/total with percentage
struct ProgressStatsSection: View {
    let completed: Int
    let total: Int
    let color: Color
    let completionLabel: String

    private var progressPercent: Double {
        total > 0 ? Double(completed) / Double(total) : 0.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Progress stats
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("\(completed)")
                    .font(AppTheme.ScaledFont.titleXLarge)
                    .foregroundStyle(color)

                Text("/ \(total) \(completionLabel)")
                    .font(AppTheme.ScaledFont.titleMedium)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(Int(progressPercent * 100))%")
                    .font(AppTheme.ScaledFont.header)
                    .foregroundStyle(progressPercent >= 1.0 ? .green : .primary)
            }

            // Progress bar
            ProgressBarView(
                progress: progressPercent,
                color: color,
                isComplete: progressPercent >= 1.0
            )
        }
        .padding(.bottom, 4)
    }
}

// MARK: - Progress Bar

/// Animated progress bar with gradient fill
struct ProgressBarView: View {
    let progress: Double
    let color: Color
    let isComplete: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 12)

                // Progress fill
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isComplete
                                ? [Color.green, Color.green.opacity(0.8)]
                                : [color, color.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: {
                            let w = geometry.size.width
                            let val = w * progress
                            return (w.isFinite && val.isFinite && val > 0) ? min(w, val) : 0
                        }(),
                        height: 12
                    )

                // Glow effect for completed
                if isComplete && progress >= 1.0 {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.green.opacity(0.2),
                                    Color.green.opacity(0.1),
                                    Color.green.opacity(0.2)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width, height: 12)
                        .blur(radius: 2)
                }
            }
        }
        .frame(height: 12)
    }
}

// MARK: - Step Dots Visualization

/// Visual dots showing individual step completion status
struct StepDotsVisualization: View {
    let steps: [any StepProtocol]
    let completedStepIDs: Set<String>
    let color: Color
    let maxSteps: Int

    init<T: StepProtocol>(steps: [T], completedStepIDs: Set<String>, color: Color, maxSteps: Int = 30) {
        self.steps = steps.map { $0 as any StepProtocol }
        self.completedStepIDs = completedStepIDs
        self.color = color
        self.maxSteps = maxSteps
    }

    var body: some View {
        if !steps.isEmpty && steps.count <= maxSteps {
            HStack(spacing: 6) {
                ForEach(0..<steps.count, id: \.self) { index in
                    let step = steps[safe: index]
                    let isCompleted = step.map { completedStepIDs.contains($0.stepID) } ?? false

                    Circle()
                        .fill(isCompleted ? color : Color.secondary.opacity(0.2))
                        .frame(width: 8, height: 8)
                        .overlay {
                            if isCompleted {
                                Circle()
                                    .stroke(color.opacity(0.3), lineWidth: 2)
                                    .scaleEffect(1.3)
                            }
                        }
                }
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Step Protocol

/// Protocol for unifying Lesson steps and WorkStep types
protocol StepProtocol {
    var stepID: String { get }
}

// Extend Lesson to conform to StepProtocol
extension Lesson: StepProtocol {
    var stepID: String { id.uuidString }
}

// Extend WorkStep to conform to StepProtocol
extension WorkStep: StepProtocol {
    var stepID: String { id.uuidString }
}

// Extend TrackStep to conform to StepProtocol
extension TrackStep: StepProtocol {
    var stepID: String { id.uuidString }
}

// MARK: - Next Item Banner

/// Banner showing the next lesson/step with colored background
struct NextItemBanner: View {
    let iconName: String
    let label: String
    let title: String
    let subtitle: String?
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 14))
                .foregroundStyle(color.opacity(0.7))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.primary)

                if let subtitle = subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.08))
        )
    }
}

// MARK: - Status Banners

/// Unified banner for completion/trophy states
struct CompletionTrophyBanner: View {
    let message: String

    var body: some View {
        StatusBannerView(
            iconName: "trophy.fill",
            message: message,
            iconGradient: [.orange, .yellow],
            textGradient: [.green, .green.opacity(0.8)],
            backgroundColor: .green.opacity(0.1),
            fontWeight: .bold
        )
    }
}

/// Unified banner for empty/no activity states
struct EmptyStateBanner: View {
    let iconName: String
    let message: String

    var body: some View {
        StatusBannerView(
            iconName: iconName,
            message: message,
            iconColor: .secondary.opacity(0.7),
            textColor: .secondary,
            backgroundColor: .secondary.opacity(0.08),
            fontWeight: .medium
        )
    }
}

/// Base banner component for status messages
private struct StatusBannerView: View {
    let iconName: String
    let message: String
    let iconGradient: [Color]?
    let textGradient: [Color]?
    let iconColor: Color?
    let textColor: Color?
    let backgroundColor: Color
    let fontWeight: Font.Weight

    init(
        iconName: String,
        message: String,
        iconGradient: [Color]? = nil,
        textGradient: [Color]? = nil,
        iconColor: Color? = nil,
        textColor: Color? = nil,
        backgroundColor: Color,
        fontWeight: Font.Weight = .medium
    ) {
        self.iconName = iconName
        self.message = message
        self.iconGradient = iconGradient
        self.textGradient = textGradient
        self.iconColor = iconColor
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.fontWeight = fontWeight
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 16))
                .foregroundStyle(
                    iconGradient.map {
                        AnyShapeStyle(LinearGradient(colors: $0, startPoint: .topLeading, endPoint: .bottomTrailing))
                    } ?? AnyShapeStyle(iconColor ?? .primary)
                )

            Text(message)
                .font(AppTheme.ScaledFont.callout)
                .fontWeight(fontWeight)
                .foregroundStyle(
                    textGradient.map {
                        AnyShapeStyle(LinearGradient(colors: $0, startPoint: .leading, endPoint: .trailing))
                    } ?? AnyShapeStyle(textColor ?? .primary)
                )

            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(backgroundColor)
        )
    }
}

// MARK: - Small Components

/// Large stats showing total activity count
struct ActivityStatsRow: View {
    let totalActivity: Int
    let color: Color

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text("\(totalActivity)")
                .font(AppTheme.ScaledFont.titleXLarge)
                .foregroundStyle(color)
            Text("total activities")
                .font(AppTheme.ScaledFont.titleMedium)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

/// Clickable badge showing activity count with icon
struct ProgressStatBadge: View {
    let count: Int
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text("\(count)")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.primary)
            Text(label)
                .font(AppTheme.ScaledFont.captionSmallSemibold)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(color.opacity(0.2), lineWidth: 1))
    }
}

/// Small row showing time since last activity
struct LastActivityRow: View {
    let lastActivityDate: Date

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text("Last activity \(lastActivityDate, style: .relative)")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }
}

/// Preview section for enrollment notes
struct NotesPreviewSection: View {
    let notes: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 14))
                .foregroundStyle(color.opacity(0.7))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("Notes")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                Text(notes)
                    .font(AppTheme.ScaledFont.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color.opacity(0.08)))
    }
}

// MARK: - Progress Card Container

/// Container styling for enrollment and report cards
struct ProgressCardContainer<Content: View>: View {
    let color: Color
    let isActive: Bool
    let content: Content

    init(color: Color, isActive: Bool = false, @ViewBuilder content: () -> Content) {
        self.color = color
        self.isActive = isActive
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(cardBackgroundColor)
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                color.opacity(isActive ? 0.3 : 0.15),
                                color.opacity(isActive ? 0.15 : 0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isActive ? 2 : 1
                    )
            )
    }

    private var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }
}
