// PresentationProgressComponents.swift
// Reusable components for presentation progress tracking views

import SwiftUI
import SwiftData

// MARK: - Stat Badge

/// Icon-based stat badge showing value and label
struct PresentationStatBadge: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(label)
                    .font(.caption2)
            }
        }
        .foregroundStyle(color)
    }
}

// MARK: - Compact Stat Badge

/// Compact badge for displaying stats in condensed format
struct PresentationCompactStatBadge: View {
    let icon: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
    }
}

// MARK: - Flag Badge

/// Badge for showing presentation flags/markers
struct PresentationFlagBadge: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "flag.fill")
            Text(text)
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.2))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }
}

// MARK: - State Badge

/// Badge showing presentation state with color coding
struct PresentationStateBadge: View {
    let state: PresentationState

    var body: some View {
        Text(state.rawValue.capitalized)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(stateColor.opacity(0.2))
            .foregroundStyle(stateColor)
            .clipShape(Capsule())
    }

    private var stateColor: Color {
        switch state {
        case .presented: return .green
        case .scheduled: return .blue
        case .draft: return .gray
        }
    }
}

// MARK: - Filter Toggle Button

/// Reusable toggle button for filtering states
struct FilterToggleButton: View {
    let icon: String
    let title: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                Text(title)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? color.opacity(0.2) : Color.gray.opacity(0.1))
            .foregroundStyle(isSelected ? color : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Progress Bar

/// Horizontal progress bar with percentage visualization
struct PresentationProgressBar: View {
    let completed: Int
    let total: Int
    let completedColor: Color

    private var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 4)

                RoundedRectangle(cornerRadius: 2)
                    .fill(percentage >= 1.0 ? Color.green : completedColor)
                    .frame(width: geo.size.width * percentage, height: 4)
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Work Progress Row

/// Row showing work item with completion status
struct WorkProgressRow: View {
    @Environment(\.modelContext) private var modelContext
    let work: WorkModel

    @State private var practiceCount: Int = 0
    @State private var student: Student?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(work.title)
                    .font(.subheadline)

                if let student = student {
                    Text(student.fullName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if practiceCount > 0 {
                    Label("\(practiceCount)", systemImage: "figure.run")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Image(systemName: work.status == .complete ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(work.status == .complete ? .green : .secondary)
            }
        }
        .padding(.vertical, 8)
        .task {
            student = work.fetchStudent(from: modelContext)
            practiceCount = work.fetchPracticeSessions(from: modelContext).count
        }
    }
}

// MARK: - Practice Session Row

/// Row showing practice session details
struct PracticeSessionRow: View {
    let session: PracticeSession

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Practice Session")
                    .font(.subheadline)

                Text(session.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let duration = session.duration {
                let minutes = Int(duration / 60)
                Text("\(minutes) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Work Item Detail Row

/// Detailed row for work item in expanded view
struct WorkItemDetailRow: View {
    let work: WorkModel

    var body: some View {
        HStack(spacing: 8) {
            // Status icon
            Image(systemName: work.status == .complete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(work.status.color)
                .font(.subheadline)

            // Work details
            VStack(alignment: .leading, spacing: 2) {
                Text(work.title)
                    .font(.subheadline)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    // Kind badge
                    if let kind = work.kind {
                        HStack(spacing: 3) {
                            Image(systemName: kind.iconName)
                                .font(.caption2)
                            Text(kind.displayName)
                                .font(.caption2)
                        }
                        .foregroundStyle(kind.color)
                    }

                    // Completion outcome
                    if let outcome = work.completionOutcome {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text(outcome.displayName)
                            .font(.caption2)
                            .foregroundStyle(outcome.color)
                    }

                    // Due date
                    if let dueAt = work.dueAt {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text(dueAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.primary.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Student Work Progress Data Model

/// Tracks a single student's progress on work from a presentation
struct StudentWorkProgress {
    var totalWork: Int = 0
    var completedWork: Int = 0
    var activeWork: Int = 0
    var reviewWork: Int = 0
    var masteredWork: Int = 0
    var needsPracticeWork: Int = 0
    var needsReviewWork: Int = 0
    var checkInsCount: Int = 0
    var workItems: [WorkModel] = []

    var isAllCompleted: Bool {
        totalWork > 0 && completedWork == totalWork
    }

    var hasWork: Bool {
        totalWork > 0
    }

    var completionPercentage: Double {
        guard totalWork > 0 else { return 0 }
        return Double(completedWork) / Double(totalWork)
    }
}

// MARK: - Student Progress Card

/// Card showing a single student's work progress with expandable details
struct StudentProgressCard: View {
    let student: Student
    let progress: StudentWorkProgress
    let modelContext: ModelContext

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with student name and progress
            headerSection

            // Compact stats when collapsed
            if !isExpanded && progress.hasWork {
                compactStatsSection
            }

            // Expanded work details
            if isExpanded && progress.hasWork {
                expandedDetailsSection
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(progress.isAllCompleted ? Color.green.opacity(0.3) : Color.primary.opacity(0.08), lineWidth: 1.5)
        )
    }

    // MARK: - Subviews

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(student.fullName)
                    .font(.headline)

                if progress.hasWork {
                    HStack(spacing: 8) {
                        // Completion status
                        HStack(spacing: 4) {
                            Image(systemName: progress.isAllCompleted ? "checkmark.circle.fill" : "circle.dashed")
                                .foregroundStyle(progress.isAllCompleted ? .green : .orange)
                            Text("\(progress.completedWork)/\(progress.totalWork)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        // Progress bar
                        PresentationProgressBar(
                            completed: progress.completedWork,
                            total: progress.totalWork,
                            completedColor: .blue
                        )
                    }
                } else {
                    Text("No work assigned")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if progress.hasWork {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var compactStatsSection: some View {
        HStack(spacing: 12) {
            if progress.activeWork > 0 {
                PresentationCompactStatBadge(icon: "circle", value: "\(progress.activeWork)", color: .blue)
            }

            if progress.reviewWork > 0 {
                PresentationCompactStatBadge(icon: "eye", value: "\(progress.reviewWork)", color: .orange)
            }

            if progress.masteredWork > 0 {
                PresentationCompactStatBadge(icon: "star.fill", value: "\(progress.masteredWork)", color: .green)
            }

            if progress.needsPracticeWork > 0 {
                PresentationCompactStatBadge(icon: "repeat", value: "\(progress.needsPracticeWork)", color: .purple)
            }

            if progress.checkInsCount > 0 {
                PresentationCompactStatBadge(icon: "checklist", value: "\(progress.checkInsCount)", color: .teal)
            }
        }
    }

    private var expandedDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            // Work items grouped by status
            ForEach(WorkStatus.allCases, id: \.self) { status in
                let statusWork = progress.workItems.filter { $0.status == status }
                if !statusWork.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: status.iconName)
                                .font(.caption)
                            Text(status.rawValue.capitalized)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(status.color)

                        ForEach(statusWork) { work in
                            WorkItemDetailRow(work: work)
                        }
                    }
                }
            }
        }
    }
}
