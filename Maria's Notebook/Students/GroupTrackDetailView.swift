// GroupTrackDetailView.swift
// Detail view for a group-based track showing lessons in order with optional student progress

import OSLog
import SwiftData
import SwiftUI

struct GroupTrackDetailView: View {
    private static let logger = Logger.students

    @Environment(\.modelContext) private var modelContext

    let subject: String
    let group: String
    /// Optional student to show progress for. If nil, shows track structure only.
    var student: Student?

    @Query(sort: [SortDescriptor(\Lesson.subject), SortDescriptor(\Lesson.orderInGroup)])
    private var allLessons: [Lesson]

    @Query private var allLessonPresentations: [LessonPresentation]

    private var groupTrack: GroupTrack? {
        do {
            return try GroupTrackService.getGroupTrack(subject: subject, group: group, modelContext: modelContext)
        } catch {
            Self.logger.warning("Failed to fetch group track: \(error)")
            return nil
        }
    }

    private var effectiveTrackSettings: (isSequential: Bool, isExplicitlyDisabled: Bool) {
        do {
            return try GroupTrackService.getEffectiveTrackSettings(subject: subject, group: group, modelContext: modelContext)
        } catch {
            Self.logger.warning("Failed to fetch effective track settings: \(error)")
            return (isSequential: true, isExplicitlyDisabled: false)
        }
    }

    private var lessons: [Lesson] {
        // Check if this group is a track (all groups are tracks by default unless explicitly disabled)
        guard GroupTrackService.isTrack(subject: subject, group: group, modelContext: modelContext) else {
            return []
        }

        // If we have an actual GroupTrack record, use it
        if let track = groupTrack {
            return GroupTrackService.getLessonsForTrack(track: track, allLessons: allLessons)
        }

        // No record exists = default behavior = sequential track
        // Filter and sort lessons for this group manually
        let settings = effectiveTrackSettings
        let filtered = allLessons.filter { lesson in
            lesson.subject.trimmed().caseInsensitiveCompare(subject.trimmed()) == .orderedSame &&
            lesson.group.trimmed().caseInsensitiveCompare(group.trimmed()) == .orderedSame
        }

        return filtered.sorted { lhs, rhs in
            if settings.isSequential {
                // Sequential: respect orderInGroup
                if lhs.orderInGroup != rhs.orderInGroup {
                    return lhs.orderInGroup < rhs.orderInGroup
                }
            }
            // Fallback to name for stable ordering
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// Progress state for each lesson for the given student
    private var progressByLessonID: [String: LessonPresentationState] {
        guard let student = student else { return [:] }
        let studentIDString = student.id.uuidString

        var result: [String: LessonPresentationState] = [:]
        for lp in allLessonPresentations where lp.studentID == studentIDString {
            result[lp.lessonID] = lp.state
        }
        return result
    }

    /// Progress summary for the header
    private var progressSummary: (presented: Int, practicing: Int, proficient: Int, total: Int) {
        guard student != nil else { return (0, 0, 0, lessons.count) }

        var presented = 0
        var practicing = 0
        var proficient = 0

        for lesson in lessons {
            if let state = progressByLessonID[lesson.id.uuidString] {
                switch state {
                case .presented:
                    presented += 1
                case .practicing, .readyForAssessment:
                    practicing += 1
                case .proficient:
                    proficient += 1
                }
            }
        }

        return (presented, practicing, proficient, lessons.count)
    }

    var body: some View {
        Form {
            Section("Track") {
                HStack {
                    Text("Subject:")
                    Spacer()
                    Text(subject)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Group:")
                    Spacer()
                    Text(group)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Type:")
                    Spacer()
                    let settings = effectiveTrackSettings
                    Label(
                        settings.isSequential ? "Sequential" : "Unordered",
                        systemImage: settings.isSequential ? "list.number" : "list.bullet"
                    )
                    .foregroundStyle(.secondary)
                }
            }

            // Progress summary section (only when student is provided)
            if student != nil {
                Section("Progress") {
                    let summary = progressSummary
                    let remaining = summary.total - summary.presented - summary.practicing - summary.proficient

                    HStack(spacing: 16) {
                        progressBadge(count: summary.proficient, label: "Mastered", color: .green, icon: "checkmark.seal.fill")
                        progressBadge(count: summary.practicing, label: "Practicing", color: .purple, icon: "arrow.triangle.2.circlepath")
                        progressBadge(count: summary.presented, label: "Presented", color: .blue, icon: "eye.fill")
                        progressBadge(count: remaining, label: "Remaining", color: .gray, icon: "circle.dashed")
                    }
                    .frame(maxWidth: .infinity)

                    // Progress bar
                    if summary.total > 0 {
                        let proficientPercent = Double(summary.proficient) / Double(summary.total)
                        let practicingPercent = Double(summary.practicing) / Double(summary.total)
                        let presentedPercent = Double(summary.presented) / Double(summary.total)

                        GeometryReader { geometry in
                            HStack(spacing: 2) {
                                if summary.proficient > 0 {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.green)
                                        .frame(width: geometry.size.width * proficientPercent)
                                }
                                if summary.practicing > 0 {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.purple)
                                        .frame(width: geometry.size.width * practicingPercent)
                                }
                                if summary.presented > 0 {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.blue)
                                        .frame(width: geometry.size.width * presentedPercent)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .frame(height: 8)
                        .background(Color.gray.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }

            Section("Lessons") {
                if lessons.isEmpty {
                    Text("No lessons in this group.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(Array(lessons.enumerated()), id: \.element.id) { index, lesson in
                        LessonStepRow(
                            lesson: lesson,
                            stepNumber: effectiveTrackSettings.isSequential ? index + 1 : nil,
                            progressState: student != nil ? progressByLessonID[lesson.id.uuidString] : nil
                        )
                    }
                }
            }
        }
        .navigationTitle("\(subject) · \(group)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private func progressBadge(count: Int, label: String, color: Color, icon: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(color)
                Text("\(count)")
                    .font(AppTheme.ScaledFont.calloutBold)
                    .foregroundStyle(color)
            }
            Text(label)
                .font(AppTheme.ScaledFont.captionSmallSemibold)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LessonStepRow: View {
    let lesson: Lesson
    let stepNumber: Int?
    let progressState: LessonPresentationState?

    var body: some View {
        HStack {
            // Progress indicator
            if let state = progressState {
                progressIcon(for: state)
                    .frame(width: 24)
            } else if stepNumber != nil {
                // Show step number only if no progress state
                Text("\(stepNumber!).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(lesson.name.isEmpty ? "Untitled Lesson" : lesson.name)
                    .font(.body)
                    .foregroundStyle(progressState == .proficient ? .secondary : .primary)
                    .strikethrough(progressState == .proficient, color: .secondary.opacity(0.5))

                if !lesson.subheading.isEmpty {
                    Text(lesson.subheading)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Status label
            if let state = progressState {
                Text(statusLabel(for: state))
                    .font(.caption)
                    .foregroundStyle(statusColor(for: state))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor(for: state).opacity(0.1), in: Capsule())
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func progressIcon(for state: LessonPresentationState) -> some View {
        switch state {
        case .presented:
            Image(systemName: "eye.fill")
                .font(.system(size: 14))
                .foregroundStyle(.blue)
        case .practicing, .readyForAssessment:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 14))
                .foregroundStyle(.purple)
        case .proficient:
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 14))
                .foregroundStyle(AppColors.success)
        }
    }

    private func statusLabel(for state: LessonPresentationState) -> String {
        switch state {
        case .presented:
            return "Presented"
        case .practicing:
            return "Practicing"
        case .readyForAssessment:
            return "Ready"
        case .proficient:
            return "Mastered"
        }
    }

    private func statusColor(for state: LessonPresentationState) -> Color {
        switch state {
        case .presented:
            return .blue
        case .practicing, .readyForAssessment:
            return .purple
        case .proficient:
            return .green
        }
    }
}
