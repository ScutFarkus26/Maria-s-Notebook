// PresentationsInboxView+Sidebar.swift
// Students sidebar extracted from PresentationsInboxView

import SwiftUI

extension PresentationsInboxView {
    // MARK: - Students Sidebar

    @ViewBuilder
    var studentsNeedingLessonsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
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

            Divider()

            // Student list
            ScrollView {
                if studentsNeedingLessons.isEmpty {
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
                } else {
                    LazyVStack(spacing: AppTheme.Spacing.xsmall) {
                        ForEach(studentsNeedingLessons, id: \.id) { student in
                            studentRow(student)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.small)
                    .padding(.top, AppTheme.Spacing.small)
                }
            }
        }
        .frame(width: 220)
    }

    // MARK: - Students Needing Lessons

    /// Students who don't have any scheduled presentations
    /// Sorted by days since last lesson, oldest first (students who haven't had a lesson longest come first)
    var studentsNeedingLessons: [Student] {
        // Find all student IDs that have a scheduled lesson
        let scheduledStudentIDs: Set<UUID> = {
            var ids = Set<UUID>()
            for la in lessonAssignments where la.scheduledFor != nil && !la.isGiven {
                ids.formUnion(la.resolvedStudentIDs)
            }
            return ids
        }()

        // Filter search
        let trimmedSearch = debouncedSearchText.trimmed().lowercased()

        // Filter to students without scheduled lessons
        let unscheduledStudents = cachedStudents.filter { student in
            // Check if student has no scheduled lessons
            guard !scheduledStudentIDs.contains(student.id) else { return false }

            // Apply search filter
            if !trimmedSearch.isEmpty {
                let name = StudentFormatter.displayName(for: student).lowercased()
                if !name.contains(trimmedSearch) { return false }
            }

            return true
        }

        // Sort by days since last lesson (oldest first = highest days first, then Int.max for never)
        return unscheduledStudents.sorted { a, b in
            let daysA = daysSinceLastLessonByStudent[a.id] ?? Int.max
            let daysB = daysSinceLastLessonByStudent[b.id] ?? Int.max
            // Sort descending: students with more days since last lesson come first
            return daysA > daysB
        }
    }

    @ViewBuilder
    // swiftlint:disable:next function_body_length
    func studentRow(_ student: Student) -> some View {
        let isSelected = coordinator.selectedStudentFilter == student.id

        HStack(spacing: AppTheme.Spacing.small) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                Text(StudentFormatter.displayName(for: student))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                // Days since last lesson - compact format
                if let days = daysSinceLastLessonByStudent[student.id] {
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

            Spacer()

            // Days badge for quick scanning
            if let days = daysSinceLastLessonByStudent[student.id], days != Int.max && days > 0 {
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
        .padding(.horizontal, AppTheme.Spacing.small + AppTheme.Spacing.xxsmall)
        .padding(.vertical, AppTheme.Spacing.small)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous)
                .fill(
                    isSelected
                        ? Color.orange.opacity(UIConstants.OpacityConstants.accent + 0.05)
                        : Color.primary.opacity(UIConstants.OpacityConstants.veryFaint)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous)
                .stroke(isSelected ? Color.orange : Color.clear, lineWidth: UIConstants.StrokeWidth.thick)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            adaptiveWithAnimation(.easeInOut(duration: 0.15)) {
                if coordinator.selectedStudentFilter == student.id {
                    coordinator.clearStudentFilter()
                } else {
                    coordinator.filterByStudent(student.id)
                }
            }
        }
    }
}
