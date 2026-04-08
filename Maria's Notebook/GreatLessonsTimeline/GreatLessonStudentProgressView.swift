// GreatLessonStudentProgressView.swift
// Drill-down view showing per-student progress within a Great Lesson branch.

import SwiftUI

struct GreatLessonStudentProgressView: View {
    let branch: GreatLessonBranch

    private var gl: GreatLesson { branch.greatLesson }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                branchHeader
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Subject breakdown
                subjectBreakdown
                    .padding(.horizontal)

                Divider()
                    .padding(.horizontal)

                // Student list
                studentList
                    .padding(.horizontal)
            }
            .padding(.bottom, 24)
        }
        .navigationTitle(gl.shortName)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Branch Header

    private var branchHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: gl.icon)
                .font(.title)
                .foregroundStyle(gl.color)
                .frame(width: 48, height: 48)
                .background(
                    gl.color.opacity(UIConstants.OpacityConstants.medium),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(gl.displayName)
                    .font(.title3)
                    .fontWeight(.bold)

                Text(gl.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Subject Breakdown

    private var subjectBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Subjects & Groups")
                .font(.subheadline)
                .fontWeight(.semibold)

            ForEach(branch.subjectGroups) { group in
                HStack(spacing: 8) {
                    Circle()
                        .fill(AppColors.color(forSubject: group.subject))
                        .frame(width: 8, height: 8)

                    Text(group.subject)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)

                    Text(group.group)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(group.lessons.count) lessons")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Student List

    private var studentList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Student Progress")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(branch.studentsWithPresentations)/\(branch.studentProgress.count)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(
                        branch.studentsWithGaps == 0 ? AppColors.success : AppColors.warning
                    )
            }

            if branch.studentProgress.isEmpty {
                Text("No students enrolled")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(branch.studentProgress) { student in
                        studentRow(student)
                    }
                }
            }
        }
    }

    private func studentRow(_ student: StudentBranchProgress) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                // Initials circle
                Text(student.initials)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        AppColors.color(forLevel: student.level).gradient,
                        in: Circle()
                    )

                // Name + level
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(student.firstName) \(student.lastName)")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack(spacing: 6) {
                        Text(student.level.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if let date = student.lastPresentedAt {
                            Text("·")
                                .font(.caption2)
                                .foregroundStyle(.quaternary)
                            Text("Last: \(date, format: .dateTime.month(.abbreviated).day())")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Spacer()

                // Count
                Text("\(student.presentedCount)/\(student.totalLessons)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(student.presentedCount > 0 ? gl.color : Color.secondary)
            }

            // Progress bar
            progressBar(value: student.completionPercentage)

            // Gap subjects
            if !student.gapSubjects.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(student.gapSubjects, id: \.self) { subject in
                        Text(subject)
                            .font(.system(size: 9))
                            .foregroundStyle(AppColors.warning)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(AppColors.warning.opacity(UIConstants.OpacityConstants.light))
                            )
                    }
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Progress Bar

    private func progressBar(value: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(gl.color.opacity(UIConstants.OpacityConstants.light))

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(gl.color.gradient)
                    .frame(width: max(0, geo.size.width * value))
            }
        }
        .frame(height: 6)
    }
}
