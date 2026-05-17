// StudentsNeedingLessonsView.swift
// Standalone view of the students-needing-lessons sidebar. Used:
//   - Inline (220px wide) as the trailing sidebar in PresentationsInboxView.
//   - Full-width as the "Students" tab in PresentationsCompactView.
//
// Tapping a row toggles `coordinator.selectedStudentFilter`. Default sort is
// by days-since-last-lesson, descending (longest gap first).

import SwiftUI
import CoreData

struct StudentsNeedingLessonsView: View {
    let viewModel: PresentationsViewModel
    let coordinator: PresentationsCoordinator
    let filterState: PresentationsFilterState
    /// All non-given lesson assignments. Used to determine which students
    /// already have a scheduled lesson and should be omitted from the list.
    let lessonAssignments: [CDLessonAssignment]
    let showAboutCard: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                if studentsNeedingLessons.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: AppTheme.Spacing.xsmall) {
                        ForEach(studentsNeedingLessons, id: \.objectID) { student in
                            studentRow(student)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.small)
                    .padding(.top, AppTheme.Spacing.small)
                }

                if showAboutCard {
                    AboutSuggestionsCard()
                        .padding(.horizontal, AppTheme.Spacing.small)
                        .padding(.top, AppTheme.Spacing.medium)
                        .padding(.bottom, AppTheme.Spacing.small)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Text("Students")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppColors.warning)
            Spacer()
            if !studentsNeedingLessons.isEmpty {
                Text("\(studentsNeedingLessons.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, AppTheme.Spacing.compact)
                    .padding(.vertical, AppTheme.Spacing.xsmall)
                    .background(Capsule().fill(.orange))
            }
        }
        .padding(.horizontal, AppTheme.Spacing.compact)
        .padding(.vertical, AppTheme.Spacing.compact)
        .background(.regularMaterial)
    }

    private var emptyState: some View {
        VStack(spacing: AppTheme.Spacing.small) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("All scheduled")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppTheme.Spacing.xxlarge + AppTheme.Spacing.medium)
    }

    // MARK: - Student computations

    /// Students with no scheduled (and not-yet-given) presentation, sorted by
    /// days-since-last-lesson (longest gap first).
    var studentsNeedingLessons: [CDStudent] {
        let scheduledStudentIDs: Set<UUID> = {
            var ids = Set<UUID>()
            for la in lessonAssignments where la.scheduledFor != nil && !la.isGiven {
                ids.formUnion(la.resolvedStudentIDs)
            }
            return ids
        }()

        let trimmedSearch = filterState.debouncedSearchText.trimmed().lowercased()
        let daysSince = viewModel.daysSinceLastLessonByStudent

        let unscheduledStudents = viewModel.cachedStudents.filter { student in
            guard let sid = student.id, !scheduledStudentIDs.contains(sid) else { return false }
            if !trimmedSearch.isEmpty {
                let name = StudentFormatter.displayName(for: student).lowercased()
                if !name.contains(trimmedSearch) { return false }
            }
            return true
        }

        return unscheduledStudents.sorted { a, b in
            let daysA = a.id.flatMap { daysSince[$0] } ?? Int.max
            let daysB = b.id.flatMap { daysSince[$0] } ?? Int.max
            return daysA > daysB
        }
    }

    // MARK: - Row

    private func studentRow(_ student: CDStudent) -> some View {
        let studentID: UUID = student.id ?? UUID()
        let isSelected: Bool = coordinator.selectedStudentFilter == studentID
        return studentRowContent(student: student, studentID: studentID, isSelected: isSelected)
    }

    private func studentRowContent(student: CDStudent, studentID: UUID, isSelected: Bool) -> some View {
        let bgColor: Color = isSelected
            ? Color.orange.opacity(UIConstants.OpacityConstants.accent + 0.05)
            : Color.primary.opacity(UIConstants.OpacityConstants.veryFaint)
        let borderColor: Color = isSelected ? Color.orange : Color.clear
        let cornerRadius: CGFloat = UIConstants.CornerRadius.medium

        return HStack(spacing: AppTheme.Spacing.small) {
            studentRowInfo(student)
            Spacer()
            studentDaysBadge(student)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, AppTheme.Spacing.small + AppTheme.Spacing.xxsmall)
        .padding(.vertical, AppTheme.Spacing.small)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(bgColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(borderColor, lineWidth: UIConstants.StrokeWidth.thick)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            toggleStudentFilter(studentID)
        }
    }

    private func toggleStudentFilter(_ studentID: UUID) {
        adaptiveWithAnimation(.easeInOut(duration: 0.15)) {
            if coordinator.selectedStudentFilter == studentID {
                coordinator.clearStudentFilter()
            } else {
                coordinator.filterByStudent(studentID)
            }
        }
    }

    @ViewBuilder
    private func studentRowInfo(_ student: CDStudent) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
            Text(StudentFormatter.displayName(for: student))
                .font(.subheadline.weight(.medium))
                .lineLimit(1)

            if let days: Int = student.id.flatMap({ viewModel.daysSinceLastLessonByStudent[$0] }) {
                if days == Int.max {
                    Text("No lessons")
                        .font(.caption2)
                        .foregroundStyle(AppColors.warning)
                } else if days == 0 {
                    Text("Today")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(days)d ago")
                        .font(.caption2)
                        .foregroundStyle(days >= 3 ? AppColors.warning : .secondary)
                }
            } else {
                Text("No lessons")
                    .font(.caption2)
                    .foregroundStyle(AppColors.warning)
            }
        }
    }

    @ViewBuilder
    private func studentDaysBadge(_ student: CDStudent) -> some View {
        let days: Int? = student.id.flatMap { viewModel.daysSinceLastLessonByStudent[$0] }
        if let days, days != Int.max && days > 0 {
            Text("\(days)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(days >= 3 ? .white : .secondary)
                .frame(width: AppTheme.Spacing.large, height: AppTheme.Spacing.medium + AppTheme.Spacing.xsmall)
                .background {
                    if days >= 3 {
                        RoundedRectangle(cornerRadius: AppTheme.Spacing.xsmall)
                            .fill(.orange)
                    } else {
                        RoundedRectangle(cornerRadius: AppTheme.Spacing.xsmall)
                            .fill(Color.primary.opacity(UIConstants.OpacityConstants.light))
                    }
                }
        }
    }
}
